import CoreImage
import XCTest
@testable import PocketFilmLab

/// Open / clear / new file / cancel while work is queued: stale results are never
/// shown or shared, and temp copies and previews are removed after queued work.
@MainActor
final class LifecycleTests: XCTestCase {
    private var bridge: RawBridge!

    override func setUpWithError() throws {
        for url in [TestData.proRAW, TestData.bayer] where !FileManager.default.fileExists(atPath: url.path) {
            throw XCTSkip("Run tools/fetch_test_raws.sh first: \(url.lastPathComponent)")
        }
        bridge = RawBridge()
    }

    /// Copies a sample the way the pickers do (into the bridge's own temp folder) and opens it.
    private func open(_ source: URL) async throws -> URL {
        let copy = try XCTUnwrap(bridge.adopt(source))
        let reply = try await call { self.bridge.startSession(url: copy, reply: $0) }
        XCTAssertNotNil(reply["width"], "\(reply)")
        return copy
    }

    private func call(_ body: (@escaping (Any?, String?) -> Void) -> Void) async throws -> [String: Any] {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<[String: Any], Error>) in
            body { value, error in
                if let error { c.resume(throwing: NSError(domain: "bridge", code: 1, userInfo: [NSLocalizedDescriptionKey: error])) }
                else { c.resume(returning: value as? [String: Any] ?? [:]) }
            }
        }
    }

    /// Waits until everything already on the render queue has run.
    private func drain() async throws { _ = try await call { self.bridge.userContentControllerLooks($0) } }

    private let settings: [String: Any] = ["settings": ["look": "vision3-250d-2383", "grain": 0.35, "halation": 0.3], "maxEdge": 1600.0]

    func testSlowRenderThenClearIsDroppedAndCleanedUp() async throws {
        let copy = try await open(TestData.proRAW)
        // First render after open decodes the RAW (~0.5 s): clear while it runs.
        let pending = Task { @MainActor in try await self.call { self.bridge.render(self.settings, reply: $0) } }
        try await Task.sleep(nanoseconds: 50_000_000)
        bridge.clear()
        let reply = try await pending.value
        XCTAssertEqual(reply["stale"] as? Bool, true, "a render for a cleared file is never shown: \(reply)")
        try await drain()
        XCTAssertFalse(FileManager.default.fileExists(atPath: copy.path), "temp copy removed after queued work")
        XCTAssertEqual(PreviewStore.shared.count, 0, "previews dropped")
        do {
            _ = try await call { self.bridge.render(self.settings, reply: $0) }
            XCTFail("render after clear must fail")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("No RAW file open"))
        }
    }

    func testSlowRenderThenNewFileShowsOnlyTheNewFile() async throws {
        let first = try await open(TestData.proRAW)
        let pending = Task { @MainActor in try await self.call { self.bridge.render(self.settings, reply: $0) } }
        try await Task.sleep(nanoseconds: 50_000_000)
        let second = try await open(TestData.bayer)
        let stale = try await pending.value
        XCTAssertEqual(stale["stale"] as? Bool, true, "\(stale)")
        let fresh = try await call { self.bridge.render(self.settings, reply: $0) }
        let url = try XCTUnwrap(fresh["url"] as? String)
        let jpeg = try XCTUnwrap(PreviewStore.shared.get(path: URL(string: url)!.path))
        let image = try XCTUnwrap(CIImage(data: jpeg))
        XCTAssertGreaterThan(image.extent.width, image.extent.height, "landscape Bayer, not the portrait ProRAW")
        try await drain()
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.path), "old copy removed")
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
        bridge.clear()
    }

    func testRapidSlidersOnlyShowTheNewest() async throws {
        _ = try await open(TestData.bayer)
        var replies: [[String: Any]] = []
        try await withThrowingTaskGroup(of: [String: Any].self) { group in
            for i in 0..<6 {
                var body = settings
                body["settings"] = ["exposure": Double(i) * 0.1]
                group.addTask { @MainActor in try await self.call { self.bridge.render(body, reply: $0) } }
            }
            for try await r in group { replies.append(r) }
        }
        XCTAssertEqual(replies.filter { $0["url"] != nil }.count, 1, "intermediate drags dropped: \(replies.map { $0.keys.sorted() })")
        bridge.clear()
    }

    func testExportAfterClearIsNeverShared() async throws {
        _ = try await open(TestData.bayer)
        let before = Self.exportFiles()
        let done = expectation(description: "export done")
        var shared: URL?, message: String?
        bridge.renderExport(["settings": [:] as [String: Any], "format": "heic"]) { file, _, error in
            shared = file; message = error; done.fulfill()
        }
        bridge.clear()
        await fulfillment(of: [done], timeout: 60)
        XCTAssertNil(shared)
        XCTAssertEqual(message, "The photo was closed before the export finished.")
        XCTAssertEqual(Self.exportFiles(), before, "the stale render was deleted")
    }

    func testExportWhileOpenGivesAFileThenNothingIsLeft() async throws {
        _ = try await open(TestData.bayer)
        let done = expectation(description: "export done")
        var shared: URL?
        bridge.renderExport(["settings": [:] as [String: Any], "format": "jpeg"]) { file, _, _ in shared = file; done.fulfill() }
        await fulfillment(of: [done], timeout: 60)
        let file = try XCTUnwrap(shared)
        let props = Pixels.properties(file)
        XCTAssertEqual(props[kCGImagePropertyPixelWidth as String] as? Int, 4032)
        try FileManager.default.removeItem(at: file) // what the share sheet's completion does
        bridge.clear()
    }

    func testCancelledPickerKeepsTheOpenFile() async throws {
        _ = try await open(TestData.bayer)
        let reply = try await call { reply in
            self.bridge.beginOpen(reply: reply)
            self.bridge.documentPickerWasCancelled(UIDocumentPickerViewController(forOpeningContentTypes: [.rawImage]))
        }
        XCTAssertEqual(reply["cancelled"] as? Bool, true)
        let still = try await call { self.bridge.render(self.settings, reply: $0) }
        XCTAssertNotNil(still["url"], "a cancelled picker does not close the current file")
        bridge.clear()
    }

    /// Clear while a picker is open, then the picker returns a file: the page was closed,
    /// so the late pick must not open a session, and its temp copy must not linger.
    func testClearWhilePickerPendingIgnoresTheLatePick() async throws {
        var replies: [[String: Any]] = []
        bridge.beginOpen { value, _ in replies.append(value as? [String: Any] ?? [:]) }
        bridge.clear()
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.rawImage])
        bridge.documentPicker(picker, didPickDocumentsAt: [TestData.bayer])
        try await drain()
        try await drain() // startSession's reply hops queue -> main
        XCTAssertFalse(bridge.hasSession, "a late pick after clear must not open a file")
        XCTAssertFalse(replies.contains { $0["width"] != nil }, "no session reply after clear: \(replies)")
        XCTAssertNil(bridge.openCopyDirectory, "no temp copy left behind")
    }

    func testFailedImportReportsAnError() async throws {
        let broken = tempURL("broken.heic")
        try Data("not an image".utf8).write(to: broken)
        defer { try? FileManager.default.removeItem(at: broken) }
        do {
            _ = try await call { self.bridge.startSession(url: broken, reply: $0) }
            XCTFail("expected an error")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }

    /// Images whose extent does not start at (0, 0) render and export the same pixels.
    func testNonZeroExtentRendersTheSame() throws {
        let engine = FilmEngine()
        let linear = try RawDecoder(url: TestData.bayer).decode(scale: 0.1)
        let zero = linear.transformed(by: CGAffineTransform(translationX: -linear.extent.minX, y: -linear.extent.minY))
        let shifted = zero.transformed(by: CGAffineTransform(translationX: 37, y: 59))
        var s = FilmSettings(); s.grain = 0.35; s.halation = 0.3; s.softness = 0.5
        let a = Pixels.bytes(try engine.applyFilm(to: zero, settings: s), context: engine.context)
        let b = try engine.applyFilm(to: shifted, settings: s)
        XCTAssertEqual(b.extent.origin, CGPoint(x: 37, y: 59))
        let bb = Pixels.bytes(b, context: engine.context)
        var diff = 0
        for i in 0..<min(a.count, bb.count) { diff = max(diff, abs(Int(a[i]) - Int(bb[i]))) }
        XCTAssertLessThanOrEqual(diff, 2, "grain field is anchored to the extent")
        let out = tempURL("shifted.jpg")
        defer { try? FileManager.default.removeItem(at: out) }
        try FilmExporter(context: engine.context, quality: 0.95).write(b, format: .jpeg, to: out)
        XCTAssertEqual(Pixels.properties(out)[kCGImagePropertyPixelWidth as String] as? Int, Int(zero.extent.width))
    }

    static func exportFiles() -> [String] {
        let tmp = FileManager.default.temporaryDirectory
        return ((try? FileManager.default.contentsOfDirectory(atPath: tmp.path)) ?? []).filter { $0.hasPrefix("film-") }.sorted()
    }
}
