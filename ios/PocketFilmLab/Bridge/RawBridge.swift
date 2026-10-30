import PhotosUI
import UIKit
import UniformTypeIdentifiers
import WebKit

/// `window.webkit.messageHandlers.raw`: lets the web UI drive the native RAW engine.
/// The page never sees RAW bytes; it sends settings and gets preview image URLs back.
///
/// Messages (all reply with a JSON object, or an error string):
///   {cmd: "looks"}                         -> {looks: [{id, label}]}
///   {cmd: "open", source: "photos"|"files"} -> {name, width, height, wbTemp, wbTint} or {cancelled: true}
///                                             or {fallback: {url, name}} for a JPEG/PNG/HEIC (web path)
///   {cmd: "render", settings, compare?}     -> {url, ms, width, height} or {stale: true}
///   {cmd: "export", settings, format}       -> {shared: Bool, ms}
///   {cmd: "clear"}                          -> {cleared: true}; drops the session, its temp copy and previews
///
/// Lifecycle: every open/clear bumps `epoch`. Work queued for an older epoch is
/// dropped before it is shown or shared, and temp files are removed on the render
/// queue, after any work already queued for them.
final class RawBridge: NSObject {
    static let name = "raw"

    weak var webView: WKWebView?
    private let engine = FilmEngine()
    private let queue = DispatchQueue(label: "film.render", qos: .userInitiated)
    private var session: RawSession?
    private var renderGeneration = 0
    /// Bumped on every new file and on clear. Main thread only.
    private(set) var epoch = 0
    private var pendingOpen: ((URL?) -> Void)?
    private var openDir: URL?

    private var presenter: UIViewController? { webView?.window?.rootViewController }
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
        switch cmd {
        case "looks": looks(replyHandler)
        case "open": open(source: body["source"] as? String ?? "photos", reply: replyHandler)
        case "render": render(body, reply: replyHandler)
        case "export": export(body, reply: replyHandler)
        case "clear": clear(); replyHandler(["cleared": true], nil)
        default: replyHandler(nil, "Unknown command \(cmd)")
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

    /// `looks` for tests: replies after all work already queued (a barrier).
    func userContentControllerLooks(_ reply: @escaping (Any?, String?) -> Void) { looks(reply) }

    /// Closes the current file: no session, no temp copy, no previews. Main thread.
    /// Work already queued for the old file finds a newer epoch and is dropped.
    func clear() {
        epoch += 1
        renderGeneration += 1
        session = nil
        let dir = openDir
        openDir = nil
        queue.async {
            if let dir { try? FileManager.default.removeItem(at: dir) }
            PreviewStore.shared.removeAll()
        }
    }

    // MARK: open

    private func open(source: String, reply: @escaping (Any?, String?) -> Void) {
        guard let presenter else { reply(nil, "No window"); return }
        beginOpen(reply: reply)
        if source == "files" {
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.rawImage, .jpeg, .png, .heic, .heif], asCopy: true)
            picker.delegate = self
            presenter.present(picker, animated: true)
        } else {
            var config = PHPickerConfiguration()
            config.filter = .images
            config.selectionLimit = 1
            config.preferredAssetRepresentationMode = .current
            let picker = PHPickerViewController(configuration: config)
            picker.delegate = self
            presenter.present(picker, animated: true)
        }
    }

    /// Waits for a picker result. A cancelled picker replies {cancelled: true} and leaves
    /// the current file open.
    func beginOpen(reply: @escaping (Any?, String?) -> Void) {
        pendingOpen = { [weak self] url in
            guard let self else { return }
            guard let url else { reply(["cancelled": true], nil); return }
            self.startSession(url: url, reply: reply)
        }
    }

    /// Opens a RAW file we own (already copied). Also the entry point for tests.
    func startSession(url: URL, reply: @escaping (Any?, String?) -> Void) {
        // A new file: anything queued for the previous one is now stale.
        epoch += 1
        renderGeneration += 1
        session = nil
        let epoch = epoch
        queue.async {
            guard FallbackImage.isRaw(url) else { return self.handOff(url, epoch: epoch, reply: reply) }
            do {
                let session = try RawSession(url: url, engine: self.engine)
                DispatchQueue.main.async {
                    guard epoch == self.epoch else { reply(["stale": true], nil); return }
                    self.session = session
                    reply([
                        "name": url.lastPathComponent,
                        "width": Int(session.nativeSize.width),
                        "height": Int(session.nativeSize.height),
                        "wbTemp": Double(session.asShot.temperature),
                        "wbTint": Double(session.asShot.tint),
                    ], nil)
                }
            } catch {
                DispatchQueue.main.async { reply(nil, error.localizedDescription) }
            }
        }
    }

    /// Not RAW: serve the photo to the page, which develops it on its JPEG/PNG path.
    private func handOff(_ url: URL, epoch: Int, reply: @escaping (Any?, String?) -> Void) {
        do {
            let (data, name) = try FallbackImage.prepare(url, context: engine.context)
            let served = PreviewStore.shared.put(data, ext: name.lowercased().hasSuffix(".png") ? "png" : "jpg")
            DispatchQueue.main.async {
                guard epoch == self.epoch else { reply(["stale": true], nil); return }
                self.session = nil
                reply(["fallback": ["url": served, "name": name]], nil)
            }
        } catch {
            DispatchQueue.main.async { reply(nil, error.localizedDescription) }
        }
    }

    /// Copies the picked file into our own temp folder (the picker's copy is
    /// removed when its callback returns). The original is never written.
    func adopt(_ source: URL) -> URL? {
        if let old = openDir {
            // After any queued work that still reads the old copy.
            queue.async { try? FileManager.default.removeItem(at: old) }
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("raw-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let dest = dir.appendingPathComponent(source.lastPathComponent)
            try FileManager.default.copyItem(at: source, to: dest)
            openDir = dir
            return dest
        } catch {
            return nil
        }
    }

    private func finishOpen(_ url: URL?) {
        let done = pendingOpen
        pendingOpen = nil
        done?(url)
    }

    // MARK: render / export

    func render(_ body: [String: Any], reply: @escaping (Any?, String?) -> Void) {
        guard let session else { reply(nil, "No RAW file open"); return }
        let settings = Self.settings(from: body["settings"])
        let compare = body["compare"] as? Bool ?? false
        let edge = CGFloat(min(max(body["maxEdge"] as? Double ?? 1600, 320), 2048))
        renderGeneration += 1
        let generation = renderGeneration
        queue.async {
            // A newer request is already queued: skip this one so slider drags don't pile up.
            if generation != self.currentGeneration() {
                DispatchQueue.main.async { reply(["stale": true], nil) }
                return
            }
            let start = CFAbsoluteTimeGetCurrent()
            do {
                let jpeg = try session.previewJPEG(settings: settings, maxEdge: edge, compare: compare)
                let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
                DispatchQueue.main.async {
                    // Cleared or another file opened while this rendered: never show it.
                    guard self.session === session else { reply(["stale": true], nil); return }
                    reply(["url": PreviewStore.shared.put(jpeg), "ms": ms], nil)
                }
                // Idle work after the preview is out: get the WB fitter ready. Runs on
                // the render queue, so it only delays a render that is already waiting. If it
                // fails, the first WB change builds the fitter itself and reports the error.
                if session.needsWhiteBalancePrewarm {
                    self.queue.async {
                        // Skip if a newer render or another file is waiting.
                        guard generation == self.currentGeneration(), self.currentSession() === session else { return }
                        try? session.prepareWhiteBalance()
                    }
                }
            } catch {
                DispatchQueue.main.async { reply(nil, error.localizedDescription) }
            }
        }
    }

    private func currentGeneration() -> Int {
        DispatchQueue.main.sync { renderGeneration }
    }

    private func currentSession() -> RawSession? {
        DispatchQueue.main.sync { session }
    }

    private func export(_ body: [String: Any], reply: @escaping (Any?, String?) -> Void) {
        renderExport(body) { file, ms, error in
            guard let file else { reply(nil, error); return }
            self.share(file, ms: ms, reply: reply)
        }
    }

    /// Full-size render to a temp file. Calls back on the main thread with the file, or
    /// an error. If the file was cleared or replaced meanwhile, the render is deleted and
    /// never shared: a stale photo must not reach the share sheet.
    func renderExport(_ body: [String: Any], done: @escaping (URL?, Double, String?) -> Void) {
        guard let session else { done(nil, 0, "No RAW file open"); return }
        var settings = Self.settings(from: body["settings"])
        settings.grainSeed = CGFloat.random(in: 0...10_000).rounded()
        let format = FilmExportFormat(rawValue: body["format"] as? String ?? "heic") ?? .heic
        queue.async {
            let start = CFAbsoluteTimeGetCurrent()
            do {
                let file = try session.export(settings: settings, format: format)
                let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
                DispatchQueue.main.async {
                    guard self.session === session else {
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

extension RawBridge: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider else { finishOpen(nil); return }
        let types = provider.registeredTypeIdentifiers.compactMap(UTType.init)
        // RAW first; otherwise the photo's own JPEG/PNG/HEIC goes to the web path.
        let type = types.first { $0.conforms(to: .rawImage) }
            ?? types.first { $0.conforms(to: .jpeg) || $0.conforms(to: .png) || $0.conforms(to: .heic) || $0.conforms(to: .heif) }
            ?? types.first { $0.conforms(to: .image) }
        guard let type else {
            return failOpen("That item is not a photo.")
        }
        provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { [weak self] url, _ in
            let copy = url.flatMap { self?.adopt($0) }
            DispatchQueue.main.async { self?.finishOpen(copy) }
        }
    }

    private func failOpen(_ message: String) {
        // Surfaced to the page as a JS error by the pending reply.
        webView?.evaluateJavaScript("window.__rawOpenError && window.__rawOpenError(\(Self.jsString(message)))")
        finishOpen(nil)
    }

    static func jsString(_ s: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: [s])
        let json = data.flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]"
        return String(json.dropFirst().dropLast())
    }
}

extension RawBridge: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        finishOpen(urls.first.flatMap(adopt))
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        finishOpen(nil)
    }
}
