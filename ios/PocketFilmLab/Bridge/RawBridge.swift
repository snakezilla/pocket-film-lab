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
///   {cmd: "render", settings, compare?}     -> {url, ms, width, height} or {stale: true}
///   {cmd: "export", settings, format}       -> {shared: Bool, ms}
final class RawBridge: NSObject {
    static let name = "raw"

    weak var webView: WKWebView?
    private let engine = FilmEngine()
    private let queue = DispatchQueue(label: "film.render", qos: .userInitiated)
    private var session: RawSession?
    private var renderGeneration = 0
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
        guard let body = message.body as? [String: Any], let cmd = body["cmd"] as? String else {
            replyHandler(nil, "Bad message")
            return
        }
        switch cmd {
        case "looks": looks(replyHandler)
        case "open": open(source: body["source"] as? String ?? "photos", reply: replyHandler)
        case "render": render(body, reply: replyHandler)
        case "export": export(body, reply: replyHandler)
        default: replyHandler(nil, "Unknown command \(cmd)")
        }
    }

    private func looks(_ reply: @escaping (Any?, String?) -> Void) {
        let list = FilmEngine.lookIDs.compactMap { id -> [String: String]? in
            guard let lut = try? engine.lut(id) else { return nil }
            return ["id": id, "label": lut.meta.label]
        }
        reply(["looks": list], nil)
    }

    // MARK: open

    private func open(source: String, reply: @escaping (Any?, String?) -> Void) {
        guard let presenter else { reply(nil, "No window"); return }
        pendingOpen = { [weak self] url in
            guard let self else { return }
            guard let url else { reply(["cancelled": true], nil); return }
            self.startSession(url: url, reply: reply)
        }
        if source == "files" {
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.rawImage], asCopy: true)
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

    /// Opens a RAW file we own (already copied). Also the entry point for tests.
    func startSession(url: URL, reply: @escaping (Any?, String?) -> Void) {
        queue.async {
            do {
                let session = try RawSession(url: url, engine: self.engine)
                DispatchQueue.main.async {
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

    /// Copies the picked file into our own temp folder (the picker's copy is
    /// removed when its callback returns). The original is never written.
    private func adopt(_ source: URL) -> URL? {
        if let old = openDir { try? FileManager.default.removeItem(at: old) }
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

    private func render(_ body: [String: Any], reply: @escaping (Any?, String?) -> Void) {
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
                let url = PreviewStore.shared.put(jpeg)
                let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
                DispatchQueue.main.async { reply(["url": url, "ms": ms], nil) }
            } catch {
                DispatchQueue.main.async { reply(nil, error.localizedDescription) }
            }
        }
    }

    private func currentGeneration() -> Int {
        DispatchQueue.main.sync { renderGeneration }
    }

    private func export(_ body: [String: Any], reply: @escaping (Any?, String?) -> Void) {
        guard let session else { reply(nil, "No RAW file open"); return }
        var settings = Self.settings(from: body["settings"])
        settings.grainSeed = CGFloat.random(in: 0...10_000).rounded()
        let format = FilmExportFormat(rawValue: body["format"] as? String ?? "heic") ?? .heic
        queue.async {
            let start = CFAbsoluteTimeGetCurrent()
            do {
                let file = try session.export(settings: settings, format: format)
                let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
                DispatchQueue.main.async { self.share(file, ms: ms, reply: reply) }
            } catch {
                DispatchQueue.main.async { reply(nil, error.localizedDescription) }
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
        let type = provider.registeredTypeIdentifiers
            .compactMap(UTType.init)
            .first { $0.conforms(to: .rawImage) }
        guard let type else {
            return failOpen("That photo has no RAW version. Pick a ProRAW or DNG photo.")
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
