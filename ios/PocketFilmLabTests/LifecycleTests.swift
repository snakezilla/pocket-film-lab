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

    /// Copies a sample the way the pickers do (into a temp folder) and opens it as a
    /// one-photo batch. Returns the copy and its item id.
    private func open(_ source: URL) async throws -> (copy: URL, id: String) {
        let copy = try XCTUnwrap(RawBridge.copyToTemp(source))
        let reply = try await call { self.bridge.startBatch(.init(urls: [copy], skipped: 0, truncated: 0), reply: $0) }
        let items = try XCTUnwrap(reply["items"] as? [[String: Any]], "\(reply)")
        XCTAssertEqual(items.first?["kind"] as? String, "raw")
        return (copy, try XCTUnwrap(items.first?["id"] as? String))
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
    private func drain() async {
        await withCheckedContinuation { c in bridge.drainQueue { c.resume() } }
    }

    private func body(_ id: String, _ extra: [String: Any] = [:]) -> [String: Any] {
        var b: [String: Any] = ["id": id, "settings": ["look": "vision3-250d-2383", "grain": 0.35, "halation": 0.3], "maxEdge": 1600.0]
        for (k, v) in extra { b[k] = v }
        return b
    }

    func testSlowRenderThenClearIsDroppedAndCleanedUp() async throws {
        let (copy, id) = try await open(TestData.proRAW)
        // First render after open decodes the RAW (~0.5 s): clear while it runs.
        let pending = Task { @MainActor in try await self.call { self.bridge.render(self.body(id), reply: $0) } }
        try await Task.sleep(nanoseconds: 50_000_000)
        bridge.clear()
        let reply = try await pending.value
        XCTAssertEqual(reply["stale"] as? Bool, true, "a render for a cleared file is never shown: \(reply)")
        await drain()
        XCTAssertFalse(FileManager.default.fileExists(atPath: copy.path), "temp copy removed after queued work")
        XCTAssertEqual(PreviewStore.shared.count, 0, "previews dropped")
        XCTAssertEqual(bridge.sessions.count, 0, "sessions dropped")
        do {
            _ = try await call { self.bridge.render(self.body(id), reply: $0) }
            XCTFail("render after clear must fail")
        } catch {
            XCTAssertEqual(error.localizedDescription, RawBridge.closedMessage)
        }
    }

    func testSlowRenderThenNewFileShowsOnlyTheNewFile() async throws {
        let first = try await open(TestData.proRAW)
        let pending = Task { @MainActor in try await self.call { self.bridge.render(self.body(first.id), reply: $0) } }
        try await Task.sleep(nanoseconds: 50_000_000)
        let second = try await open(TestData.bayer)
        let stale = try await pending.value
        XCTAssertEqual(stale["stale"] as? Bool, true, "\(stale)")
        do {
            _ = try await call { self.bridge.render(self.body(first.id), reply: $0) }
            XCTFail("an id from the old batch must not render")
        } catch {
            XCTAssertEqual(error.localizedDescription, RawBridge.closedMessage)
        }
        let fresh = try await call { self.bridge.render(self.body(second.id), reply: $0) }
        let url = try XCTUnwrap(fresh["url"] as? String)
        let jpeg = try XCTUnwrap(PreviewStore.shared.get(path: URL(string: url)!.path))
        let image = try XCTUnwrap(CIImage(data: jpeg))
        XCTAssertGreaterThan(image.extent.width, image.extent.height, "landscape Bayer, not the portrait ProRAW")
        await drain()
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.copy.path), "old copy removed")
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.copy.path))
        bridge.clear()
    }

    func testRapidSlidersOnlyShowTheNewest() async throws {
        let (_, id) = try await open(TestData.bayer)
        var replies: [[String: Any]] = []
        try await withThrowingTaskGroup(of: [String: Any].self) { group in
            for i in 0..<6 {
                let body = self.body(id, ["settings": ["exposure": Double(i) * 0.1]])
                group.addTask { @MainActor in try await self.call { self.bridge.render(body, reply: $0) } }
            }
            for try await r in group { replies.append(r) }
        }
        XCTAssertEqual(replies.filter { $0["url"] != nil }.count, 1, "intermediate drags dropped: \(replies.map { $0.keys.sorted() })")
        bridge.clear()
    }

    func testExportAfterClearIsNeverShared() async throws {
        let (_, id) = try await open(TestData.bayer)
        let before = Self.exportFiles()
        let done = expectation(description: "export done")
        var shared: URL?, message: String?
        bridge.renderExport(["id": id, "settings": [:] as [String: Any], "format": "heic"]) { file, _, error in
            shared = file; message = error; done.fulfill()
        }
        bridge.clear()
        await fulfillment(of: [done], timeout: 60)
        XCTAssertNil(shared)
        XCTAssertEqual(message, RawBridge.closedWhileSavingMessage)
        XCTAssertEqual(Self.exportFiles(), before, "the stale render was deleted")
    }

    func testExportWhileOpenGivesAFileThenNothingIsLeft() async throws {
        let (_, id) = try await open(TestData.bayer)
        let done = expectation(description: "export done")
        var shared: URL?
        bridge.renderExport(["id": id, "settings": [:] as [String: Any], "format": "jpeg"]) { file, _, _ in shared = file; done.fulfill() }
        await fulfillment(of: [done], timeout: 60)
        let file = try XCTUnwrap(shared)
        let props = Pixels.properties(file)
        XCTAssertEqual(props[kCGImagePropertyPixelWidth as String] as? Int, 4032)
        try FileManager.default.removeItem(at: file) // what the share sheet's completion does
        bridge.clear()
    }

    func testCancelledPickerKeepsTheOpenFile() async throws {
        let (_, id) = try await open(TestData.bayer)
        let reply = try await call { reply in
            self.bridge.beginOpen(reply: reply)
            self.bridge.documentPickerWasCancelled(UIDocumentPickerViewController(forOpeningContentTypes: [.rawImage]))
        }
        XCTAssertEqual(reply["cancelled"] as? Bool, true)
        let still = try await call { self.bridge.render(self.body(id), reply: $0) }
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
        await drain() // the copy runs on the render queue, then hops to main
        await drain()
        XCTAssertFalse(bridge.hasItems, "a late pick after clear must not open a file")
        XCTAssertFalse(replies.contains { $0["items"] != nil }, "no batch reply after clear: \(replies)")
        XCTAssertTrue(bridge.copyDirs.isEmpty, "no temp copy left behind")
    }

    func testFailedImportReportsAnError() async throws {
        let broken = try XCTUnwrap(RawBridge.copyToTemp(try { () throws -> URL in
            let url = tempURL("broken.heic")
            try Data("not an image".utf8).write(to: url)
            return url
        }()))
        let reply = try await call { self.bridge.startBatch(.init(urls: [broken], skipped: 0, truncated: 0), reply: $0) }
        let id = try XCTUnwrap((reply["items"] as? [[String: Any]])?.first?["id"] as? String)
        do {
            _ = try await call { self.bridge.handle("source", ["id": id], reply: $0) }
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error.localizedDescription, RawBridge.oopsMessage)
        }
        bridge.clear()
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
