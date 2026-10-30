import WebKit
import XCTest
@testable import PocketFilmLab

/// The web UI -> native engine bridge, end to end in a real WKWebView with the bundled page.
@MainActor
final class BridgeTests: XCTestCase {
    func testSettingsAreClampedAndValidated() {
        let s = RawBridge.settings(from: [
            "look": "portra400-2383", "strength": 3.0, "exposure": -9.0, "grain": 0.5,
            "halation": -1.0, "wbTemp": 5200.0, "wbTint": 400.0,
        ])
        XCTAssertEqual(s.lookID, "portra400-2383")
        XCTAssertEqual(s.strength, 1)
        XCTAssertEqual(s.exposure, -4)
        XCTAssertEqual(s.grain, 0.5)
        XCTAssertEqual(s.halation, 0)
        XCTAssertEqual(s.whiteBalance, WhiteBalance(temperature: 5200, tint: 150))
        let bad = RawBridge.settings(from: ["look": "../../etc", "grain": "x"])
        XCTAssertEqual(bad.lookID, FilmEngine.defaultLookID)
        XCTAssertNil(bad.whiteBalance)
    }

    /// Slider-drag latency: postMessage -> native render -> preview JPEG served over app:// -> decoded.
    func testPreviewRoundTripLatency() async throws {
        let bridge = RawBridge()
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(BundleSchemeHandler(), forURLScheme: BundleSchemeHandler.scheme)
        config.userContentController.addScriptMessageHandler(bridge, contentWorld: .page, name: RawBridge.name)
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 402, height: 874), configuration: config)
        bridge.webView = web
        let loaded = expectation(description: "page loaded")
        let nav = NavDelegate { loaded.fulfill() }
        web.navigationDelegate = nav
        web.load(URLRequest(url: URL(string: "app://local/index.html")!))
        await fulfillment(of: [loaded], timeout: 30)

        let copy = tempURL("bridge.dng")
        try FileManager.default.copyItem(at: TestData.proRAW, to: copy)
        defer { try? FileManager.default.removeItem(at: copy) }
        let opened = expectation(description: "opened")
        var info: [String: Any] = [:]
        bridge.startSession(url: copy) { value, error in
            XCTAssertNil(error)
            info = value as? [String: Any] ?? [:]
            opened.fulfill()
        }
        await fulfillment(of: [opened], timeout: 30)
        XCTAssertGreaterThan(info["width"] as? Int ?? 0, 1000)

        let js = """
        const out = [];
        for (let i = 0; i < 8; i++) {
          const t0 = performance.now();
          const r = await window.webkit.messageHandlers.raw.postMessage({ cmd: 'render', maxEdge: 1206,
            settings: { look: 'vision3-250d-2383', strength: 1, exposure: i * 0.1, grain: 0.35, halation: 0.3 } });
          const img = new Image(); img.src = r.url; await img.decode();
          out.push([performance.now() - t0, r.ms, img.naturalWidth, img.naturalHeight]);
        }
        return out;
        """
        let result = try await web.callAsyncJavaScript(js, contentWorld: .page) as? [[Double]] ?? []
        XCTAssertEqual(result.count, 8)
        // The first render includes the one-off linear decode; the rest are slider moves.
        let first = result[0]
        let drags = result.dropFirst().map { $0[0] }.sorted()
        let nativeMs = result.dropFirst().map { $0[1] }.sorted()
        let median = drags[drags.count / 2]
        print(String(format: "BRIDGE first %.0f ms (native %.0f); drag median %.0f ms (native %.0f), max %.0f ms; preview %.0fx%.0f",
                     first[0], first[1], median, nativeMs[nativeMs.count / 2], drags.last!, first[2], first[3]))
        XCTAssertEqual(max(first[2], first[3]), 1206, accuracy: 2)
        XCTAssertLessThan(median, 1000, "bridge is usable at all")
    }
}

private final class NavDelegate: NSObject, WKNavigationDelegate {
    let done: () -> Void
    init(done: @escaping () -> Void) { self.done = done }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { done() }
}
