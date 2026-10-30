import CoreImage
import XCTest
@testable import PocketFilmLab

/// Writes each look on each sample RAW to ios/TestData/renders/<timestamp>/ (gitignored)
/// for judging by eye. Each run gets a new folder; earlier renders are kept.
final class LookSheetTests: XCTestCase {
    func testWriteLookSheet() throws {
        let engine = FilmEngine()
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "")
        let dir = TestData.dir.appendingPathComponent("renders").appendingPathComponent(stamp)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for raw in [TestData.proRAW, TestData.bayer] {
            let base = raw.deletingPathExtension().lastPathComponent
            var plain = FilmSettings(); plain.strength = 0
            try write(engine, try engine.render(raw: raw, settings: plain, maxPixelSize: 1600), dir, "\(base)-plain")
            for id in FilmEngine.lookIDs {
                var s = FilmSettings(); s.lookID = id; s.grain = 0.35; s.halation = 0.3
                try write(engine, try engine.render(raw: raw, settings: s, maxPixelSize: 1600), dir, "\(base)-\(id)")
            }
        }
    }

    private func write(_ engine: FilmEngine, _ image: CIImage, _ dir: URL, _ name: String) throws {
        let url = dir.appendingPathComponent("\(name).jpg")
        try FilmExporter(context: engine.context, quality: 0.9).write(image, format: .jpeg, to: url)
    }
}
