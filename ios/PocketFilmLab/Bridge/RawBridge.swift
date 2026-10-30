import UIKit
import UniformTypeIdentifiers
import WebKit

/// `window.webkit.messageHandlers.raw`: lets the web UI drive the native engine for a
/// batch of picked photos. The page never sees RAW bytes; it sends settings and gets
/// preview image URLs back.
///
/// Messages (all reply with a JSON object, or an error string):
///   {cmd: "looks"}                          -> {looks: [{id, label}]}
///   {cmd: "open", source: "photos"|"files"}  -> {items: [{id, kind: "raw"|"photo", name}], skipped, truncated}
///                                              or {cancelled: true} / {stale: true}
///   {cmd: "source", id}                     -> {url, name}: a non-RAW photo as JPEG/PNG for the web path
///   {cmd: "render", id, settings, compare?, maxEdge?, hero?}
///                                           -> {url, ms, info: {width, height, wbTemp, wbTint}} or {stale: true}
///   {cmd: "export", id, settings, format}   -> {shared: Bool, ms}: full size to the share sheet
///   {cmd: "saveAccess"}                     -> {access: "authorized"|"limited"|"denied"|...}
///   {cmd: "save", id, settings, format}     -> {saved: true, ms}: full size into Photos
///   {cmd: "saveData", name, data}           -> {saved: true}: a JPEG the page made, into Photos
///   {cmd: "openSettings"}                   -> {opened: true}
///   {cmd: "clear"}                          -> {cleared: true}; drops the batch, its temp copies and previews
///
/// Lifecycle: every open/clear bumps `epoch`. Work queued for an older epoch is
/// dropped before it is shown, shared or saved, and temp files are removed on the
/// render queue, after any work already queued for them.
final class RawBridge: NSObject {
    static let name = "raw"
    /// The most photos one pick keeps. Each is copied to temp storage until cleared.
    static let maxBatch = 50

    struct Item {
        let url: URL
        let isRaw: Bool
    }

    weak var webView: WKWebView?
    var saver: PhotoSaving = SystemPhotoSaver()
    let engine = FilmEngine()
    let queue = DispatchQueue(label: "film.render", qos: .userInitiated)
    /// Render queue only.
    let sessions: SessionCache
    /// Main thread only: the open batch, its temp folders, request bookkeeping.
    private(set) var items: [String: Item] = [:]
    var copyDirs: [URL] = []
    private var renderGeneration: [String: Int] = [:]
    private var nextItem = 0
    /// Bumped on every new batch and on clear. Main thread only.
    private(set) var epoch = 0
    var pendingOpen: ((PickResult?) -> Void)?
    /// Bumped when a picker opens and on clear, so a picker result that arrives after
    /// clear (or for an older picker) is dropped. Main thread only.
    var openToken = 0

    struct PickResult {
        let urls: [URL]
        let skipped: Int
        let truncated: Int
    }

    override init() {
        sessions = SessionCache(engine: engine)
        super.init()
    }

    var presenter: UIViewController? { webView?.window?.rootViewController }

    /// For tests.
    var hasItems: Bool { !items.isEmpty }
}

extension RawBridge: WKScriptMessageHandlerWithReply {
    func userContentController(
        _ controller: WKUserContentController,
        didReceive message: WKScriptMessage,
        replyHandler: @escaping (Any?, String?) -> Void
    ) {
        guard WebSecurity.isTrusted(message) else { replyHandler(nil, "Untrusted sender"); return }
        guard let body = message.body as? [String: Any], let cmd = body["cmd"] as? String else {
            replyHandler(nil, "Bad message")
            return
        }
        handle(cmd, body, reply: replyHandler)
    }

    /// Routes one command. Main thread. Also the entry point for tests.
    func handle(_ cmd: String, _ body: [String: Any], reply: @escaping (Any?, String?) -> Void) {
        switch cmd {
        case "looks": looks(reply)
        case "open": open(source: body["source"] as? String ?? "photos", reply: reply)
        case "source": source(body, reply: reply)
        case "render": render(body, reply: reply)
        case "export": export(body, reply: reply)
        case "saveAccess": saver.requestAccess { reply(["access": $0.rawValue], nil) }
        case "save": save(body, reply: reply)
        case "saveData": saveData(body, reply: reply)
        case "openSettings": openSettings(reply)
        case "clear": clear(); reply(["cleared": true], nil)
        default: reply(nil, "Unknown command \(cmd)")
        }
    }

    private func looks(_ reply: @escaping (Any?, String?) -> Void) {
        // On the render queue: the engine's LUT cache is only touched there.
        queue.async {
            let list = FilmEngine.lookIDs.compactMap { id -> [String: String]? in
                guard let lut = try? self.engine.lut(id) else { return nil }
                return ["id": id, "label": lut.meta.label]
            }
            DispatchQueue.main.async { reply(["looks": list], nil) }
        }
    }

    /// Replies after all work already on the render queue (a barrier). For tests.
    func drainQueue(_ done: @escaping () -> Void) {
        queue.async { DispatchQueue.main.async(execute: done) }
    }

    /// Closes the batch: no items, no sessions, no temp copies, no previews. Main thread.
    /// Work already queued for the old batch finds a newer epoch and is dropped.
    func clear() {
        // A picker still open: answer it as cancelled now; its later result is dropped.
        openToken += 1
        finishOpen(nil)
        replaceBatch(with: [])
    }

    /// Makes `urls` (copies we own) the open batch and returns their item ids. Main thread.
    @discardableResult
    func replaceBatch(with urls: [URL]) -> [(id: String, item: Item)] {
        epoch += 1
        renderGeneration = [:]
        let oldDirs = copyDirs
        copyDirs = urls.map { $0.deletingLastPathComponent() }
        let entries = urls.map { url -> (id: String, item: Item) in
            nextItem += 1
            return ("i\(nextItem)", Item(url: url, isRaw: FallbackImage.isRaw(url)))
        }
        items = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0.item) })
        queue.async {
            self.sessions.removeAll()
            for dir in oldDirs { try? FileManager.default.removeItem(at: dir) }
            PreviewStore.shared.removeAll()
        }
        return entries
    }

    /// Opens picked copies as the new batch and replies with the item list. Main thread.
    func startBatch(_ pick: PickResult, reply: @escaping (Any?, String?) -> Void) {
        let kept = Array(pick.urls.prefix(Self.maxBatch))
        for extra in pick.urls.dropFirst(Self.maxBatch) {
            try? FileManager.default.removeItem(at: extra.deletingLastPathComponent())
        }
        guard !kept.isEmpty else { reply(nil, "Those files could not be read as photos."); return }
        let entries = replaceBatch(with: kept)
        reply([
            "items": entries.map { ["id": $0.id, "kind": $0.item.isRaw ? "raw" : "photo", "name": $0.item.url.lastPathComponent] },
            "skipped": pick.skipped,
            "truncated": pick.truncated + max(0, pick.urls.count - Self.maxBatch),
        ], nil)
    }

    func item(_ body: [String: Any]) -> (id: String, item: Item)? {
        guard let id = body["id"] as? String, let item = items[id] else { return nil }
        return (id, item)
    }

    static let closedMessage = "That photo is no longer open."

    // MARK: source (non-RAW photos)

    private func source(_ body: [String: Any], reply: @escaping (Any?, String?) -> Void) {
        guard let (_, item) = item(body) else { reply(nil, Self.closedMessage); return }
        let epoch = epoch
        queue.async {
            do {
                let served = try FallbackImage.servable(item.url, context: self.engine.context)
                let url = PreviewStore.shared.putFile(served.file)
                DispatchQueue.main.async {
                    guard epoch == self.epoch else { reply(["stale": true], nil); return }
                    reply(["url": url, "name": served.name], nil)
                }
            } catch {
                DispatchQueue.main.async { reply(nil, error.localizedDescription) }
            }
        }
    }

    // MARK: render

    func render(_ body: [String: Any], reply: @escaping (Any?, String?) -> Void) {
        guard let (id, item) = item(body) else { reply(nil, Self.closedMessage); return }
        guard item.isRaw else { reply(nil, "Not a RAW photo."); return }
        let settings = Self.settings(from: body["settings"])
        let compare = body["compare"] as? Bool ?? false
        let hero = body["hero"] as? Bool ?? true
        let edge = CGFloat(min(max(body["maxEdge"] as? Double ?? 1600, 320), 2048))
        // Film and compare renders are counted apart: holding compare must not drop a film render.
        let slot = compare ? "\(id)#orig" : id
        let generation = (renderGeneration[slot] ?? 0) + 1
        renderGeneration[slot] = generation
        let epoch = epoch
        queue.async {
            // A newer request for this photo is already queued: skip this one so slider drags don't pile up.
            guard self.onMain({ self.epoch == epoch && self.renderGeneration[slot] == generation }) else {
                DispatchQueue.main.async { reply(["stale": true], nil) }
                return
            }
            let start = CFAbsoluteTimeGetCurrent()
            do {
                let session = try self.sessions.session(id: id, url: item.url, hero: hero)
                let jpeg = try session.previewJPEG(settings: settings, maxEdge: edge, compare: compare)
                let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
                let info: [String: Any] = [
                    "width": Int(session.nativeSize.width), "height": Int(session.nativeSize.height),
                    "wbTemp": Double(session.asShot.temperature), "wbTint": Double(session.asShot.tint),
                ]
                DispatchQueue.main.async {
                    // Cleared or another batch opened while this rendered: never show it.
                    guard epoch == self.epoch else { reply(["stale": true], nil); return }
                    let url = PreviewStore.shared.put(jpeg, key: "\(id)-\(compare ? "orig" : "film")")
                    reply(["url": url, "ms": ms, "info": info], nil)
                }
                self.prewarm(session, id: id, slot: slot, generation: generation, epoch: epoch)
            } catch {
                DispatchQueue.main.async { reply(nil, error.localizedDescription) }
            }
        }
    }

    /// Idle work after a preview is out: get the WB fitter ready. Runs on the render
    /// queue, so it only delays a render that is already waiting. If it fails, the first
    /// WB change builds the fitter itself and reports the error.
    private func prewarm(_ session: RawSession, id: String, slot: String, generation: Int, epoch: Int) {
        guard session.needsWhiteBalancePrewarm else { return }
        queue.async {
            // Skip if a newer render for this photo, or another batch, is waiting.
            guard self.onMain({ self.epoch == epoch && self.renderGeneration[slot] == generation }),
                  self.sessions.existing(id: id) === session else { return }
            try? session.prepareWhiteBalance()
        }
    }

    /// Reads main-thread state from the render queue.
    private func onMain<T>(_ read: () -> T) -> T {
        DispatchQueue.main.sync(execute: read)
    }

    // MARK: export / save

    /// Full-size render of one RAW to a temp file. Calls back on the main thread with the
    /// file, or an error. If the batch was cleared or replaced meanwhile, the render is
    /// deleted and never shared or saved: a stale photo must not leave the app.
    func renderExport(_ body: [String: Any], done: @escaping (URL?, Double, String?) -> Void) {
        guard let (id, item) = item(body) else { done(nil, 0, Self.closedMessage); return }
        guard item.isRaw else { done(nil, 0, "Not a RAW photo."); return }
        var settings = Self.settings(from: body["settings"])
        settings.grainSeed = CGFloat.random(in: 0...10_000).rounded()
        let format = FilmExportFormat(rawValue: body["format"] as? String ?? "heic") ?? .heic
        let epoch = epoch
        queue.async {
            let start = CFAbsoluteTimeGetCurrent()
            do {
                // A cached session is reused; otherwise a temporary one, so a batch save
                // does not push the photo on screen out of the cache.
                let session = try self.sessions.existing(id: id) ?? RawSession(url: item.url, engine: self.engine)
                let file = try session.export(settings: settings, format: format)
                let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
                DispatchQueue.main.async {
                    guard epoch == self.epoch else {
                        try? FileManager.default.removeItem(at: file)
                        done(nil, ms, "The photo was closed before the export finished.")
                        return
                    }
                    done(file, ms, nil)
                }
            } catch {
                DispatchQueue.main.async { done(nil, 0, error.localizedDescription) }
            }
        }
    }

    private func export(_ body: [String: Any], reply: @escaping (Any?, String?) -> Void) {
        renderExport(body) { file, ms, error in
            guard let file else { reply(nil, error); return }
            self.share(file, ms: ms, reply: reply)
        }
    }

    /// Develops one photo at full size and adds it to Photos. One at a time: the page
    /// waits for each reply, so a batch never holds more than one full-size render.
    func save(_ body: [String: Any], reply: @escaping (Any?, String?) -> Void) {
        renderExport(body) { file, ms, error in
            guard let file else { reply(nil, error); return }
            self.saver.save(file) { saveError in
                try? FileManager.default.removeItem(at: file)
                if let saveError { reply(nil, saveError.localizedDescription) } else { reply(["saved": true, "ms": ms], nil) }
            }
        }
    }

    /// Saves a JPEG/PNG the page developed (the web path). Only image bytes are accepted.
    func saveData(_ body: [String: Any], reply: @escaping (Any?, String?) -> Void) {
        guard let b64 = body["data"] as? String, let data = Data(base64Encoded: b64) else {
            reply(nil, "Nothing to save.")
            return
        }
        let file: URL
        do { file = try ShareBridge.prepareFile(name: body["name"] as? String ?? "", data: data) } catch {
            reply(nil, error.localizedDescription)
            return
        }
        saver.save(file) { error in
            try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
            if let error { reply(nil, error.localizedDescription) } else { reply(["saved": true], nil) }
        }
    }

    private func share(_ file: URL, ms: Double, reply: @escaping (Any?, String?) -> Void) {
        guard let presenter, let webView else {
            try? FileManager.default.removeItem(at: file)
            reply(nil, "No window")
            return
        }
        let sheet = UIActivityViewController(activityItems: [file], applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = webView
        sheet.completionWithItemsHandler = { _, completed, _, _ in
            try? FileManager.default.removeItem(at: file)
            reply(["shared": completed, "ms": ms], nil)
        }
        presenter.present(sheet, animated: true)
    }

    private func openSettings(_ reply: @escaping (Any?, String?) -> Void) {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { reply(["opened": false], nil); return }
        UIApplication.shared.open(url) { reply(["opened": $0], nil) }
    }

    /// Parses and clamps settings from the page. Unknown or bad values fall back to defaults.
    static func settings(from raw: Any?) -> FilmSettings {
        let d = raw as? [String: Any] ?? [:]
        func num(_ key: String, _ lo: Double, _ hi: Double, _ fallback: Double) -> Float {
            guard let v = d[key] as? Double, v.isFinite else { return Float(fallback) }
            return Float(min(max(v, lo), hi))
        }
        var s = FilmSettings()
        if let look = d["look"] as? String, FilmEngine.lookIDs.contains(look) { s.lookID = look }
        s.strength = num("strength", 0, 1, 1)
        s.exposure = num("exposure", -4, 4, 0)
        s.grain = num("grain", 0, 1, 0)
        s.halation = num("halation", 0, 1, 0)
        s.softness = num("softness", 0, 1, 0)
        s.warmth = num("warmth", 0, 1, 0)
        if d["wbTemp"] is Double, d["wbTint"] is Double {
            s.whiteBalance = WhiteBalance(temperature: num("wbTemp", 1800, 50_000, 6500), tint: num("wbTint", -150, 150, 0))
        }
        return s
    }
}
