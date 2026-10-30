import SwiftUI
import WebKit
import UniformTypeIdentifiers
import ImageIO

/// Hosts the bundled web build. Files are served from the app bundle under app://local/
/// so ES modules and fetch() of the LUTs work; nothing is loaded from the network.
struct WebView: UIViewRepresentable {
    final class Coordinator: NSObject, WKNavigationDelegate {
        let share = ShareBridge()
        let raw = RawBridge()

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let decision = WebSecurity.decide(url: action.request.url,
                                              isMainFrame: action.targetFrame?.isMainFrame ?? true,
                                              userTapped: action.navigationType == .linkActivated)
            if decision == .openExternally, let url = action.request.url { UIApplication.shared.open(url) }
            decisionHandler(decision == .allow ? .allow : .cancel)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(BundleSchemeHandler(), forURLScheme: BundleSchemeHandler.scheme)
        config.userContentController.addScriptMessageHandler(context.coordinator.share, contentWorld: .page, name: ShareBridge.name)
        config.userContentController.addScriptMessageHandler(context.coordinator.raw, contentWorld: .page, name: RawBridge.name)
        config.userContentController.addUserScript(
            WKUserScript(source: ShareBridge.script, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )
        let view = WKWebView(frame: .zero, configuration: config)
        #if DEBUG
        view.isInspectable = true // Safari Web Inspector in debug builds only
        #endif
        view.navigationDelegate = context.coordinator
        view.scrollView.contentInsetAdjustmentBehavior = .never
        context.coordinator.share.webView = view
        context.coordinator.raw.webView = view
        if let url = URL(string: "\(BundleSchemeHandler.scheme)://local/index.html") {
            view.load(URLRequest(url: url))
        }
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

/// Replaces navigator.share / canShare with a bridge to the native share sheet.
final class ShareBridge: NSObject {
    static let name = "share"
    static let script = """
    (() => {
      const toBase64 = (buf) => {
        let s = ''; const b = new Uint8Array(buf);
        for (let i = 0; i < b.length; i += 0x8000) s += String.fromCharCode.apply(null, b.subarray(i, i + 0x8000));
        return btoa(s);
      };
      navigator.canShare = (data) => !!(data && data.files && data.files.length);
      navigator.share = async (data) => {
        const file = data.files[0];
        const b64 = toBase64(await file.arrayBuffer());
        const ok = await window.webkit.messageHandlers.share.postMessage({ name: file.name, data: b64 });
        if (!ok) throw new DOMException('Share cancelled', 'AbortError');
      };
    })();
    """

    weak var webView: WKWebView?
}

extension ShareBridge: WKScriptMessageHandlerWithReply {
    func userContentController(
        _ controller: WKUserContentController,
        didReceive message: WKScriptMessage,
        replyHandler: @escaping (Any?, String?) -> Void
    ) {
        guard WebSecurity.isTrusted(message) else { replyHandler(nil, "Untrusted sender"); return }
        guard let body = message.body as? [String: String],
              let b64 = body["data"], let data = Data(base64Encoded: b64),
              let presenter = webView?.window?.rootViewController else {
            replyHandler(false, nil)
            return
        }
        let file: URL
        do { file = try Self.prepareFile(name: body["name"] ?? "", data: data) } catch {
            replyHandler(nil, error.localizedDescription)
            return
        }
        // Share the encoded file itself (name, format and bytes as the page made them),
        // not a re-encoded UIImage.
        let sheet = UIActivityViewController(activityItems: [file], applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = webView
        sheet.completionWithItemsHandler = { _, completed, _, _ in
            try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
            replyHandler(completed, nil)
        }
        presenter.present(sheet, animated: true)
    }

    enum ShareError: Error, LocalizedError {
        case notAnImage
        var errorDescription: String? { "The file to share is not a JPEG or PNG image." }
    }

    /// Writes the page's file to a fresh temp folder under a safe name. Only JPEG and PNG
    /// bytes are accepted, and the extension follows the bytes, not the page.
    static func prepareFile(name: String, data: Data) throws -> URL {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(src).flatMap({ UTType($0 as String) }),
              type.conforms(to: .jpeg) || type.conforms(to: .png),
              CGImageSourceGetCount(src) > 0 else { throw ShareError.notAnImage }
        let ext = type.conforms(to: .png) ? "png" : "jpg"
        let base = (URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent)
            .filter { $0.isLetter || $0.isNumber || "-_ .".contains($0) }
            .trimmingCharacters(in: .whitespaces)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("share-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("\(base.isEmpty || base.hasPrefix(".") ? "film" : base).\(ext)")
        try data.write(to: file)
        return file
    }
}

/// Serves files from the bundled `dist` folder.
final class BundleSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "app"
    private let root = Bundle.main.resourceURL!.appendingPathComponent("dist")

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url, url.host?.lowercased() == WebSecurity.host else {
            task.didFailWithError(URLError(.unsupportedURL))
            return
        }
        if let preview = PreviewStore.shared.get(path: url.path) {
            respond(task, url: url, data: preview, mime: url.path.hasSuffix(".png") ? "image/png" : "image/jpeg")
            return
        }
        guard let file = WebSecurity.resolve(url, root: root),
              let data = try? Data(contentsOf: file) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let mime = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        respond(task, url: url, data: data, mime: mime)
    }

    private func respond(_ task: WKURLSchemeTask, url: URL, data: Data, mime: String) {
        let response = HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": mime, "Content-Length": "\(data.count)"]
        )!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}
