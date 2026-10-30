import SwiftUI
import WebKit
import UniformTypeIdentifiers

/// Hosts the bundled web build. Files are served from the app bundle under app://local/
/// so ES modules and fetch() of the LUTs work; nothing is loaded from the network.
struct WebView: UIViewRepresentable {
    final class Coordinator {
        let share = ShareBridge()
        let raw = RawBridge()
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
        view.isInspectable = true
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
        guard let body = message.body as? [String: String],
              let b64 = body["data"], let data = Data(base64Encoded: b64),
              let image = UIImage(data: data),
              let presenter = webView?.window?.rootViewController else {
            replyHandler(false, nil)
            return
        }
        let sheet = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = webView
        sheet.completionWithItemsHandler = { _, completed, _, _ in replyHandler(completed, nil) }
        presenter.present(sheet, animated: true)
    }
}

/// Serves files from the bundled `dist` folder.
final class BundleSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "app"
    private let root = Bundle.main.resourceURL!.appendingPathComponent("dist")

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        let path = url.path.isEmpty || url.path == "/" ? "/index.html" : url.path
        if let preview = PreviewStore.shared.get(path: path) {
            respond(task, url: url, data: preview, mime: "image/jpeg")
            return
        }
        let file = root.appendingPathComponent(path).standardizedFileURL
        guard file.path.hasPrefix(root.standardizedFileURL.path),
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
