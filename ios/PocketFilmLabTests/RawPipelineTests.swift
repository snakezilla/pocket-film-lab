import CoreImage
import XCTest
@testable import PocketFilmLab

/// Decode + develop + export on the CC0 sample DNGs (tools/fetch_test_raws.sh).
final class RawPipelineTests: XCTestCase {
    let engine = FilmEngine()

    override func setUpWithError() throws {
        for url in [TestData.proRAW, TestData.bayer, TestData.large47MP] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "Run tools/fetch_test_raws.sh first: \(url.lastPathComponent)")
        }
    }

    func testDecodeIsSceneLinear() throws {
        // +1 EV must double linear values (where nothing clips): no tone curve in the decode.
        let decoder = RawDecoder(url: TestData.bayer)
        let a = Pixels.floats(try decoder.decode(scale: 0.05, exposure: 0), context: engine.context)
        let b = Pixels.floats(try decoder.decode(scale: 0.05, exposure: 1), context: engine.context)
        var ratios: [Float] = []
        for i in stride(from: 1, to: a.count, by: 4) where a[i] > 0.02 && a[i] < 0.4 { ratios.append(b[i] / a[i]) }
        XCTAssertGreaterThan(ratios.count, 100)
        let median = ratios.sorted()[ratios.count / 2]
        print("LINEARITY median ratio +1EV: \(median) over \(ratios.count) px")
        XCTAssertEqual(median, 2, accuracy: 0.05)
    }

    func testPreviewIsDecodedSmall() throws {
        let image = try engine.render(raw: TestData.proRAW, settings: FilmSettings(), maxPixelSize: 1280)
        XCTAssertLessThanOrEqual(max(image.extent.width, image.extent.height), 1281)
        XCTAssertGreaterThan(max(image.extent.width, image.extent.height), 1200)
    }

    func testAsShotWhiteBalanceIsRead() throws {
        let wb = try RawDecoder(url: TestData.proRAW).asShotWhiteBalance()
        print("AS-SHOT WB proRAW: \(wb)")
        XCTAssert((2000...12000).contains(wb.temperature), "\(wb)")
    }

    /// Export to JPEG and HEIC, decode the files with ImageIO and compare every pixel
    /// against the in-memory render. Also checks the original is unchanged and no metadata leaks.
    func testExportMatchesRenderPixelByPixel() throws {
        for source in [TestData.proRAW, TestData.bayer] {
            let before = try Data(contentsOf: source)
            let image = try engine.render(raw: source, settings: FilmSettings(), maxPixelSize: 1600)
            let reference = Pixels.bytes(image, context: engine.context)
            let w = Int(image.extent.width), h = Int(image.extent.height)

            for format in FilmExportFormat.allCases {
                let url = tempURL("export.\(format.fileExtension)")
                try FilmExporter(context: engine.context, quality: 1).write(image, format: format, to: url)
                guard let file = Pixels.decodeFile(url) else { return XCTFail("cannot read \(url.lastPathComponent)") }
                XCTAssertEqual(file.width, w); XCTAssertEqual(file.height, h)

                var sum = 0, maxDiff = 0, over8 = 0
                for i in 0..<(w * h * 4) where i % 4 != 3 {
                    let d = abs(Int(file.rgba[i]) - Int(reference[i]))
                    sum += d; maxDiff = max(maxDiff, d); if d > 8 { over8 += 1 }
                }
                let mean = Double(sum) / Double(w * h * 3)
                let fracOver8 = Double(over8) / Double(w * h * 3)
                print("EXPORT \(source.lastPathComponent) \(format) \(w)x\(h) mean|d|=\(mean) max=\(maxDiff) >8: \(fracOver8)")
                XCTAssertLessThan(mean, 1.5, "\(format) differs from render")
                // JPEG/HEIC subsample chroma, so single channels at hard colour edges can move
                // by 10-25 codes. Allow 1% of channels over 8 codes; the mean must stay tiny.
                XCTAssertLessThan(fracOver8, 0.01, "\(format) has too many large differences")

                let props = Pixels.properties(url)
                XCTAssertNil(props[kCGImagePropertyGPSDictionary as String], "GPS in export")
                let tiff = props[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
                XCTAssertNil(tiff?[kCGImagePropertyTIFFModel as String], "camera model leaked")
                let exif = props[kCGImagePropertyExifDictionary as String] as? [String: Any]
                XCTAssertNil(exif?[kCGImagePropertyExifDateTimeOriginal as String], "capture date leaked")
            }
            XCTAssertEqual(try Data(contentsOf: source), before, "source file changed")
        }
    }

    /// 47 MP (8424x5632) full-size HEIC export. Records the memory footprint.
    func testFullSize47MPExportMemory() throws {
        try export47MP(FilmSettings(), label: "47MP export")
    }

    /// Same with grain and halation on: the halation blur is the widest filter at full size.
    func testFullSize47MPExportMemoryWithTexture() throws {
        var s = FilmSettings(); s.grain = 0.35; s.halation = 0.3
        try export47MP(s, label: "47MP export + grain/halation")
    }

    private func export47MP(_ settings: FilmSettings, label: String) throws {
        let start = physFootprint()
        var peak = start
        let timer = DispatchSource.makeTimerSource(queue: .global())
        timer.schedule(deadline: .now(), repeating: .milliseconds(20))
        timer.setEventHandler { peak = max(peak, physFootprint()) }
        timer.resume()
        let t0 = Date()
        let image = try engine.render(raw: TestData.large47MP, settings: settings)
        let url = tempURL("full.heic")
        try FilmExporter(context: engine.context).write(image, format: .heic, to: url)
        timer.cancel()
        let elapsed = Date().timeIntervalSince(t0)
        let file = Pixels.properties(url)
        let mb = Double(peak - start) / 1_048_576
        print("MEMORY \(label): start \(start / 1_048_576) MB, peak +\(Int(mb)) MB, \(String(format: "%.1f", elapsed)) s, \(file[kCGImagePropertyPixelWidth as String] ?? "?")x\(file[kCGImagePropertyPixelHeight as String] ?? "?")")
        // CIRAWFilter applies the DNG default crop: 8424x5632 sensor -> 8368x5584.
        XCTAssertEqual(file[kCGImagePropertyPixelWidth as String] as? Int, Int(image.extent.width))
        XCTAssertGreaterThan(image.extent.width * image.extent.height, 46_000_000)
        // Budget: a 48 MP 8-bit RGBA bitmap alone is 190 MB. Allow ~4x that on top of the start.
        XCTAssertLessThan(mb, 800, "export used too much memory")
    }
}
