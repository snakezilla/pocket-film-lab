import CoreImage
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import PocketFilmLab

/// Stands in for the Photos library: records what would be saved.
final class FakeSaver: PhotoSaving {
    var access: PhotoAccess = .authorized
    var failure: Error?
    private(set) var saved: [(url: URL, existed: Bool, props: [String: Any], type: String?)] = []

    func requestAccess(_ done: @escaping (PhotoAccess) -> Void) { done(access) }

    func save(_ file: URL, done: @escaping (Error?) -> Void) {
        let src = CGImageSourceCreateWithURL(file as CFURL, nil)
        saved.append((file, FileManager.default.fileExists(atPath: file.path), Pixels.properties(file),
                      src.flatMap { CGImageSourceGetType($0) as String? }))
        DispatchQueue.main.async { done(self.failure) }
    }
}

/// Batch open, per-photo render, source serving, the session cache, and save to Photos.
@MainActor
final class BatchTests: XCTestCase {
    private var bridge: RawBridge!
    private var saver: FakeSaver!

    override func setUpWithError() throws {
        for url in [TestData.proRAW, TestData.bayer] where !FileManager.default.fileExists(atPath: url.path) {
            throw XCTSkip("Run tools/fetch_test_raws.sh first: \(url.lastPathComponent)")
        }
        bridge = RawBridge()
        saver = FakeSaver()
        bridge.saver = saver
    }

    override func tearDown() {
        bridge?.clear()
    }

    private func call(_ cmd: String, _ body: [String: Any] = [:]) async throws -> [String: Any] {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<[String: Any], Error>) in
            bridge.handle(cmd, body) { value, error in
                if let error { c.resume(throwing: NSError(domain: "bridge", code: 1, userInfo: [NSLocalizedDescriptionKey: error])) }
                else { c.resume(returning: value as? [String: Any] ?? [:]) }
            }
        }
    }

    private func openBatch(_ sources: [URL]) async throws -> [[String: Any]] {
        let copies = sources.compactMap(RawBridge.copyToTemp)
        let reply = try await withCheckedThrowingContinuation { (c: CheckedContinuation<[String: Any], Error>) in
            bridge.startBatch(.init(urls: copies, skipped: 0, truncated: 0)) { value, error in
                if let error { c.resume(throwing: NSError(domain: "bridge", code: 1, userInfo: [NSLocalizedDescriptionKey: error])) }
                else { c.resume(returning: value as? [String: Any] ?? [:]) }
            }
        }
        return try XCTUnwrap(reply["items"] as? [[String: Any]])
    }

    private func jpegSample() throws -> URL {
        try ExportPrivacyTests.writeSample(type: .jpeg, orientation: 1, gps: true)
    }

    func testBatchMixesRawAndPhotosInPickOrder() async throws {
        let jpeg = try jpegSample()
        defer { try? FileManager.default.removeItem(at: jpeg) }
        let items = try await openBatch([TestData.proRAW, jpeg, TestData.bayer])
        XCTAssertEqual(items.map { $0["kind"] as? String }, ["raw", "photo", "raw"])
        XCTAssertEqual(Set(items.compactMap { $0["id"] as? String }).count, 3, "unique ids")

        // Each RAW renders by its id: ProRAW is portrait, the Bayer sample landscape.
        for (index, portrait) in [(0, true), (2, false)] {
            let id = try XCTUnwrap(items[index]["id"] as? String)
            let reply = try await call("render", ["id": id, "settings": ["grain": 0.35] as [String: Any], "maxEdge": 800.0])
            let url = try XCTUnwrap(reply["url"] as? String)
            let image = try XCTUnwrap(CIImage(data: try XCTUnwrap(PreviewStore.shared.get(path: URL(string: url)!.path))))
            XCTAssertEqual(image.extent.height > image.extent.width, portrait, "item \(index)")
            let info = try XCTUnwrap(reply["info"] as? [String: Any])
            XCTAssertGreaterThan(info["wbTemp"] as? Double ?? 0, 1000)
        }

        // The JPEG is served for the web path, byte for byte, from disk.
        let photoID = try XCTUnwrap(items[1]["id"] as? String)
        let source = try await call("source", ["id": photoID])
        let served = try XCTUnwrap(PreviewStore.shared.get(path: URL(string: try XCTUnwrap(source["url"] as? String))!.path))
        XCTAssertEqual(served, try Data(contentsOf: jpeg))
        do {
            _ = try await call("render", ["id": photoID])
            XCTFail("a JPEG has no native render")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Not a RAW photo.")
        }
    }

    func testBatchIsCappedAndExtraCopiesAreRemoved() async throws {
        let jpeg = try jpegSample()
        defer { try? FileManager.default.removeItem(at: jpeg) }
        let copies = (0..<(RawBridge.maxBatch + 2)).compactMap { _ in RawBridge.copyToTemp(jpeg) }
        var reply: [String: Any] = [:]
        bridge.startBatch(.init(urls: copies, skipped: 1, truncated: 0)) { value, _ in reply = value as? [String: Any] ?? [:] }
        XCTAssertEqual((reply["items"] as? [[String: Any]])?.count, RawBridge.maxBatch)
        XCTAssertEqual(reply["truncated"] as? Int, 2)
        XCTAssertEqual(reply["skipped"] as? Int, 1)
        for extra in copies.suffix(2) { XCTAssertFalse(FileManager.default.fileExists(atPath: extra.path)) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: copies[0].path))
    }

    func testSessionCacheKeepsThePhotoOnScreen() throws {
        let cache = SessionCache(engine: FilmEngine(), capacity: 2)
        _ = try cache.session(id: "hero", url: TestData.bayer, hero: true)
        for id in ["a", "b", "c"] { _ = try cache.session(id: id, url: TestData.bayer, hero: false) }
        XCTAssertEqual(cache.count, 2, "memory stays bounded")
        XCTAssertEqual(cache.ids, ["hero", "c"], "the hero survives background work")
        _ = try cache.session(id: "c", url: TestData.bayer, hero: true)
        _ = try cache.session(id: "d", url: TestData.bayer, hero: false)
        XCTAssertEqual(cache.ids, ["c", "d"], "a new hero replaces the old one")
    }

    func testPreviewStoreKeepsOnePreviewPerKey() {
        let store = PreviewStore()
        let a = store.put(Data([1]), key: "i1-film")
        let b = store.put(Data([2]), key: "i1-film")
        let c = store.put(Data([3]), key: "i2-film")
        XCTAssertNil(store.get(path: URL(string: a)!.path), "replaced")
        XCTAssertEqual(store.get(path: URL(string: b)!.path), Data([2]))
        XCTAssertEqual(store.get(path: URL(string: c)!.path), Data([3]))
        XCTAssertEqual(store.count, 2)
        XCTAssertNil(store.get(path: "/elsewhere/p1.jpg"))
    }

    /// Save develops the RAW at full size as HEIC with no source metadata, hands that file to
    /// Photos, then removes it. The original copy is untouched.
    func testSaveAddsAFullSizeCleanHeicThenRemovesIt() async throws {
        let items = try await openBatch([TestData.bayer])
        let id = try XCTUnwrap(items.first?["id"] as? String)
        let original = try Data(contentsOf: TestData.bayer)
        let reply = try await call("save", ["id": id, "settings": ["grain": 0.35, "halation": 0.3] as [String: Any], "format": "heic"])
        XCTAssertEqual(reply["saved"] as? Bool, true)
        let saved = try XCTUnwrap(saver.saved.first)
        XCTAssertTrue(saved.existed)
        XCTAssertEqual(saved.type, UTType.heic.identifier)
        XCTAssertEqual(saved.props[kCGImagePropertyPixelWidth as String] as? Int, 4032)
        XCTAssertNil(saved.props[kCGImagePropertyGPSDictionary as String])
        XCTAssertNil((saved.props[kCGImagePropertyTIFFDictionary as String] as? [String: Any])?[kCGImagePropertyTIFFMake as String])
        XCTAssertFalse(FileManager.default.fileExists(atPath: saved.url.path), "temp render removed after saving")
        XCTAssertEqual(try Data(contentsOf: TestData.bayer), original)
    }

    func testSaveFailureIsReportedAndCleanedUp() async throws {
        let items = try await openBatch([TestData.bayer])
        saver.failure = SystemPhotoSaver.Failure.notAllowed
        do {
            _ = try await call("save", ["id": try XCTUnwrap(items.first?["id"] as? String), "format": "heic"])
            XCTFail("expected an error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("not allowed"), error.localizedDescription)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(saver.saved.first).url.path))
    }

    func testSaveAccessIsPassedToThePage() async throws {
        saver.access = .denied
        let reply = try await call("saveAccess")
        XCTAssertEqual(reply["access"] as? String, "denied")
        XCTAssertFalse(PhotoAccess.denied.canSave)
        XCTAssertTrue(PhotoAccess.limited.canSave)
    }

    /// The web path's JPEG is saved as is; anything that is not an image is refused.
    func testSaveDataAcceptsOnlyImages() async throws {
        let jpeg = try jpegSample()
        defer { try? FileManager.default.removeItem(at: jpeg) }
        let reply = try await call("saveData", ["name": "film-1.jpg", "data": try Data(contentsOf: jpeg).base64EncodedString()])
        XCTAssertEqual(reply["saved"] as? Bool, true)
        XCTAssertEqual(saver.saved.first?.type, UTType.jpeg.identifier)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(saver.saved.first).url.path))
        do {
            _ = try await call("saveData", ["name": "x.jpg", "data": Data("<script>".utf8).base64EncodedString()])
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(saver.saved.count, 1, "nothing else reached Photos")
        }
    }

    func testSaveAfterClearSavesNothing() async throws {
        let items = try await openBatch([TestData.bayer])
        let id = try XCTUnwrap(items.first?["id"] as? String)
        let pending = Task { @MainActor in try await self.call("save", ["id": id, "format": "heic"]) }
        await Task.yield()
        bridge.clear()
        do {
            _ = try await pending.value
            XCTFail("expected an error")
        } catch {
            XCTAssertTrue(saver.saved.isEmpty, "a closed photo never reaches Photos")
        }
    }
}
