import UniformTypeIdentifiers
import WebKit
import XCTest
@testable import PocketFilmLab

/// The privileged web view's boundary: who may message the bridges, what may load,
/// and which files the app:// handler serves.
@MainActor
final class SecurityTests: XCTestCase {
    func testOnlyTheBundledMainFrameIsTrusted() {
        XCTAssertTrue(WebSecurity.isTrustedSender(isMainFrame: true, scheme: "app", host: "local"))
        XCTAssertFalse(WebSecurity.isTrustedSender(isMainFrame: false, scheme: "app", host: "local"), "iframe")
        XCTAssertFalse(WebSecurity.isTrustedSender(isMainFrame: true, scheme: "app", host: "evil"), "other app host")
        XCTAssertFalse(WebSecurity.isTrustedSender(isMainFrame: true, scheme: "https", host: "local"))
        XCTAssertFalse(WebSecurity.isTrustedSender(isMainFrame: true, scheme: nil, host: nil))
    }

    func testNavigationPolicy() {
        func d(_ s: String, main: Bool = true, tap: Bool = false) -> WebSecurity.NavigationDecision {
            WebSecurity.decide(url: URL(string: s), isMainFrame: main, userTapped: tap)
        }
        XCTAssertEqual(d("app://local/index.html"), .allow)
        XCTAssertEqual(d("app://evil/index.html"), .cancel)
        XCTAssertEqual(d("https://github.com/JanLohse/spectral_film_lut", tap: true), .openExternally)
        XCTAssertEqual(d("https://example.com/"), .cancel, "scripted redirect, not a tap")
        XCTAssertEqual(d("https://example.com/", main: false, tap: true), .cancel, "iframe")
        XCTAssertEqual(d("http://example.com/", tap: true), .cancel)
        XCTAssertEqual(d("file:///etc/passwd"), .cancel)
        XCTAssertEqual(d("javascript:alert(1)"), .cancel)
        XCTAssertEqual(d("data:text/html,hi"), .cancel)
        XCTAssertEqual(d("about:blank", main: false), .allow)
        XCTAssertEqual(d("about:blank"), .cancel)
    }

    func testSchemeHandlerStaysInsideItsRoot() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("sec-\(UUID().uuidString)")
        let root = base.appendingPathComponent("dist")
        let sibling = base.appendingPathComponent("dist-evil")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("assets"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        try Data("ok".utf8).write(to: root.appendingPathComponent("index.html"))
        try Data("secret".utf8).write(to: sibling.appendingPathComponent("x.txt"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: sibling)

        XCTAssertEqual(WebSecurity.resolve(URL(string: "app://local/")!, root: root)?.lastPathComponent, "index.html")
        XCTAssertNotNil(WebSecurity.resolve(URL(string: "app://local/assets/a.js")!, root: root))
        XCTAssertNil(WebSecurity.resolve(URL(string: "app://local/../dist-evil/x.txt")!, root: root))
        XCTAssertNil(WebSecurity.resolve(URL(string: "app://local/%2e%2e/dist-evil/x.txt")!, root: root))
        XCTAssertNil(WebSecurity.resolve(URL(string: "app://local/link/x.txt")!, root: root), "symlink out of root")
        XCTAssertNil(WebSecurity.resolve(URL(string: "app://other/index.html")!, root: root))
        XCTAssertNil(WebSecurity.resolve(URL(string: "https://local/index.html")!, root: root))
    }

    /// A page from another origin gets a refusal from both bridges, not a session.
    func testOtherOriginCannotUseTheBridges() async throws {
        let raw = RawBridge(), share = ShareBridge()
        let config = WKWebViewConfiguration()
        config.userContentController.addScriptMessageHandler(raw, contentWorld: .page, name: RawBridge.name)
        config.userContentController.addScriptMessageHandler(share, contentWorld: .page, name: ShareBridge.name)
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 300, height: 300), configuration: config)
        let loaded = expectation(description: "loaded")
        let nav = LoadDelegate { loaded.fulfill() }
        web.navigationDelegate = nav
        web.loadHTMLString("<p>evil</p>", baseURL: URL(string: "https://evil.example/"))
        await fulfillment(of: [loaded], timeout: 10)
        let js = """
        const out = [];
        for (const [name, body] of [['raw', {cmd: 'looks'}], ['raw', {cmd: 'clear'}], ['share', {name: 'a.jpg', data: ''}]]) {
          try { await window.webkit.messageHandlers[name].postMessage(body); out.push('accepted'); }
          catch (e) { out.push(String(e.message || e)); }
        }
        return out;
        """
        let result = try await web.callAsyncJavaScript(js, contentWorld: .page) as? [String] ?? []
        XCTAssertEqual(result.count, 3)
        for r in result { XCTAssertTrue(r.contains("Untrusted sender"), r) }
    }

    /// An iframe inside the real bundled page (same origin) is refused too.
    func testIframeInTheBundledPageIsRefused() async throws {
        let raw = RawBridge()
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(BundleSchemeHandler(), forURLScheme: BundleSchemeHandler.scheme)
        config.userContentController.addScriptMessageHandler(raw, contentWorld: .page, name: RawBridge.name)
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 300, height: 300), configuration: config)
        let loaded = expectation(description: "loaded")
        let nav = LoadDelegate { loaded.fulfill() }
        web.navigationDelegate = nav
        web.load(URLRequest(url: URL(string: "app://local/index.html")!))
        await fulfillment(of: [loaded], timeout: 30)
        let main = try await web.callAsyncJavaScript(
            "return (await window.webkit.messageHandlers.raw.postMessage({cmd: 'looks'})).looks.length",
            contentWorld: .page) as? Int
        XCTAssertEqual(main, FilmEngine.lookIDs.count, "the main frame works")
        // Add a same-origin iframe, then run script inside that frame itself.
        _ = try await web.callAsyncJavaScript("""
            const f = document.createElement('iframe'); f.src = 'app://local/index.html';
            document.body.appendChild(f);
            await new Promise((r) => f.addEventListener('load', r));
            """, contentWorld: .page)
        let frame = try XCTUnwrap(nav.subframes.last, "iframe navigation seen")
        XCTAssertFalse(frame.isMainFrame)
        let js = """
        try { await window.webkit.messageHandlers.raw.postMessage({cmd: 'looks'}); return 'accepted'; }
        catch (e) { return String(e.message || e); }
        """
        let result = try await web.callAsyncJavaScript(js, in: frame, contentWorld: .page) as? String
        print("SECURITY iframe message: \(result ?? "nil")")
        XCTAssertEqual(result, "Untrusted sender")
    }

    /// The JPEG/PNG share path shares the page's encoded file, under a safe name.
    func testShareKeepsTheEncodedFile() throws {
        let jpeg = try XCTUnwrap(Self.tinyImage(type: .jpeg))
        let file = try ShareBridge.prepareFile(name: "../../film-portra.jpg", data: jpeg)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        XCTAssertEqual(file.lastPathComponent, "film-portra.jpg")
        XCTAssertTrue(file.path.hasPrefix(FileManager.default.temporaryDirectory.path))
        XCTAssertEqual(try Data(contentsOf: file), jpeg, "bytes unchanged, no re-encode")

        let png = try XCTUnwrap(Self.tinyImage(type: .png))
        let pngFile = try ShareBridge.prepareFile(name: "photo.jpg", data: png)
        defer { try? FileManager.default.removeItem(at: pngFile.deletingLastPathComponent()) }
        XCTAssertEqual(pngFile.pathExtension, "png", "extension follows the bytes")

        XCTAssertThrowsError(try ShareBridge.prepareFile(name: "x.jpg", data: Data("<html>".utf8)))
    }

    static func tinyImage(type: UTType) -> Data? {
        let ctx = CGContext(data: nil, width: 8, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.setFillColor(red: 0.5, green: 0.3, blue: 0.2, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 4))
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, type.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }
}

final class LoadDelegate: NSObject, WKNavigationDelegate {
    let done: () -> Void
    private(set) var subframes: [WKFrameInfo] = []
    init(done: @escaping () -> Void) { self.done = done }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { done() }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let frame = action.targetFrame, !frame.isMainFrame { subframes.append(frame) }
        decisionHandler(.allow)
    }
}
