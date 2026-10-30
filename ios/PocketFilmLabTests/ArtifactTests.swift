import CoreImage
import XCTest
@testable import PocketFilmLab

/// Writes the inspection artifacts to ios/TestData/artifacts/<timestamp>/ (gitignored);
/// `tools/make_artifacts.sh` copies a chosen run into measurements/artifacts/.
/// Sources are the CC0 sample DNGs only.
final class ArtifactTests: XCTestCase {
    let engine = FilmEngine()

    func testWriteArtifacts() throws {
        for url in [TestData.proRAW, TestData.bayer] where !FileManager.default.fileExists(atPath: url.path) {
            throw XCTSkip("Run tools/fetch_test_raws.sh first")
        }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "")
        let dir = TestData.dir.appendingPathComponent("artifacts").appendingPathComponent(stamp)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // 1. Shipping path: RawSession.export (full size, quality 0.95) at the UI defaults.
        var ui = FilmSettings(); ui.grain = 0.35; ui.halation = 0.3
        let session = try RawSession(url: TestData.bayer, engine: engine)
        for format in [FilmExportFormat.jpeg, .heic] {
            let file = try session.export(settings: ui, format: format)
            let dest = dir.appendingPathComponent("shipping-iphonexs-250d.\(format.fileExtension)")
            try FileManager.default.moveItem(at: file, to: dest)
            let p = Pixels.properties(dest)
            print("ARTIFACT \(dest.lastPathComponent): \(p[kCGImagePropertyPixelWidth as String] ?? 0)x\(p[kCGImagePropertyPixelHeight as String] ?? 0), keys \(p.keys.sorted())")
        }

        // 2. Grey ramp, scene-linear stops -8...+6, neutral and warm, each look.
        let stops = Array(-8...6)
        let patch: CGFloat = 64
        var ramp = CIImage.empty()
        for (i, stop) in stops.enumerated() {
            let v = CGFloat(0.18 * pow(2, Double(stop)))
            ramp = CIImage(color: CIColor(red: v, green: v, blue: v)).cropped(to: CGRect(x: CGFloat(i) * patch, y: 0, width: patch, height: patch)).composited(over: ramp)
        }
        for id in FilmEngine.lookIDs {
            for warmth in [Float(0), 1] {
                var s = FilmSettings(); s.lookID = id; s.warmth = warmth
                try write(try engine.applyFilm(to: ramp, settings: s), dir.appendingPathComponent("ramp-\(id)-warmth\(Int(warmth)).png"), .png)
            }
        }

        // 3. Look sheet: each sample, plain decode + each look, neutral and warm (grain/halation at UI defaults).
        for raw in [TestData.proRAW, TestData.bayer] {
            let base = raw.deletingPathExtension().lastPathComponent
            var plain = FilmSettings(); plain.strength = 0
            try write(try engine.render(raw: raw, settings: plain, maxPixelSize: 720), dir.appendingPathComponent("look-\(base)-plain.jpg"), .jpeg)
            for id in FilmEngine.lookIDs {
                for warmth in [Float(0), 1] {
                    var s = ui; s.lookID = id; s.warmth = warmth
                    try write(try engine.render(raw: raw, settings: s, maxPixelSize: 720), dir.appendingPathComponent("look-\(base)-\(id)-warmth\(Int(warmth)).jpg"), .jpeg)
                }
            }
        }
        print("ARTIFACT dir \(dir.path)")
    }

    private enum Kind { case jpeg, png }

    private func write(_ image: CIImage, _ url: URL, _ kind: Kind) throws {
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
        let moved = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
        switch kind {
        case .jpeg: try FilmExporter(context: engine.context, quality: 0.9).write(moved, format: .jpeg, to: url)
        case .png: try engine.context.writePNGRepresentation(of: moved, to: url, format: .RGBA8, colorSpace: sRGB)
        }
    }
}
