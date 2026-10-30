import CoreImage
import XCTest
@testable import PocketFilmLab

/// Phase 4 edge cases: rotated files, odd white balance, Bayer DNG vs ProRAW.
final class EdgeCaseTests: XCTestCase {
    let engine = FilmEngine()
    /// The iPhone XS Bayer DNG with its Orientation tag set to 8 (tools/fetch_test_raws.sh).
    static let bayerRotated = TestData.dir.appendingPathComponent("iphonexs-bayer-rot8.dng")

    override func setUpWithError() throws {
        for url in [TestData.proRAW, TestData.bayer, Self.bayerRotated] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "Run tools/fetch_test_raws.sh first: \(url.lastPathComponent)")
        }
    }

    // MARK: Rotation

    /// The ProRAW sample is stored landscape with Orientation 6. Decode, preview and
    /// export must all come out portrait, and the export must not rely on an EXIF tag.
    func testRotatedProRAWIsUprightEverywhere() throws {
        let decoder = RawDecoder(url: TestData.proRAW)
        let native = try decoder.nativeSize()
        XCTAssertGreaterThan(native.width, native.height, "sample is stored landscape")
        let linear = try decoder.decode(scale: 0.1)
        XCTAssertGreaterThan(linear.extent.height, linear.extent.width, "decode is upright (portrait)")

        let session = try RawSession(url: TestData.proRAW, engine: engine)
        let jpeg = try session.previewJPEG(settings: FilmSettings(), maxEdge: 800, compare: false)
        let preview = CIImage(data: jpeg)!
        XCTAssertEqual(preview.extent.height, 800, accuracy: 1)
        XCTAssertLessThan(preview.extent.width, preview.extent.height)

        let out = try session.export(settings: FilmSettings(), format: .jpeg)
        defer { try? FileManager.default.removeItem(at: out) }
        let props = Pixels.properties(out)
        XCTAssertEqual(props["Orientation"] as? Int ?? 1, 1)
        let w = props[kCGImagePropertyPixelWidth as String] as? Int ?? 0
        let h = props[kCGImagePropertyPixelHeight as String] as? Int ?? 0
        print("ROTATION ProRAW native \(native) -> export \(w)x\(h)")
        XCTAssertGreaterThan(h, w)
    }

    /// Same Bayer pixels, Orientation 8: the decode must equal the unrotated decode
    /// turned 90° counter-clockwise, pixel for pixel (within half-float rounding).
    func testOrientationTagRotatesPixels() throws {
        let plain = try RawDecoder(url: TestData.bayer).decode(scale: 0.1)
        let rotated = try RawDecoder(url: Self.bayerRotated).decode(scale: 0.1)
        XCTAssertEqual(rotated.extent.width, plain.extent.height, accuracy: 1)
        XCTAssertEqual(rotated.extent.height, plain.extent.width, accuracy: 1)

        let expected = plain.oriented(.left)
        let a = Pixels.bytes(try engine.applyFilm(to: atOrigin(expected), settings: FilmSettings()), context: engine.context)
        let b = Pixels.bytes(try engine.applyFilm(to: atOrigin(rotated), settings: FilmSettings()), context: engine.context)
        XCTAssertEqual(a.count, b.count)
        var sum = 0, n = 0
        for i in 0..<min(a.count, b.count) where i % 4 != 3 { sum += abs(Int(a[i]) - Int(b[i])); n += 1 }
        let mean = Double(sum) / Double(max(n, 1))
        print(String(format: "ROTATION Bayer orientation 8 vs rotated plain: mean |Δ| %.2f codes", mean))
        XCTAssertLessThan(mean, 1.0)

        // The fast white-balance path keeps the orientation too.
        let session = try RawSession(url: Self.bayerRotated, engine: engine)
        var s = FilmSettings()
        _ = try session.previewJPEG(settings: s, maxEdge: 600, compare: false)
        s.whiteBalance = WhiteBalance(temperature: session.asShot.temperature + 1000, tint: session.asShot.tint)
        let moved = CIImage(data: try session.previewJPEG(settings: s, maxEdge: 600, compare: false))!
        XCTAssertGreaterThan(moved.extent.height, moved.extent.width)
    }

    // MARK: White balance

    /// The bridge allows 1800–50 000 K and tint ±150. Every corner must render finite,
    /// in-range pixels on both file types, through the true decode and the fitted matrix,
    /// and the colour must move the right way.
    func testExtremeWhiteBalanceStaysFiniteAndInRange() throws {
        let corners: [WhiteBalance] = [
            .init(temperature: 1800, tint: -150), .init(temperature: 1800, tint: 150),
            .init(temperature: 50_000, tint: -150), .init(temperature: 50_000, tint: 150),
        ]
        // Texture on: halation and grain also see the out-of-gamut (negative) values
        // an extreme white balance produces.
        var textured = FilmSettings(); textured.grain = 0.35; textured.halation = 0.3
        for source in [TestData.proRAW, TestData.bayer] {
            let decoder = RawDecoder(url: source)
            let native = try decoder.nativeSize()
            let scale = Float(240 / max(native.width, native.height))
            var blueOverRed: [Float] = []
            for wb in corners {
                let linear = try decoder.decode(scale: scale, whiteBalance: wb)
                let film = Pixels.floats(try engine.applyFilm(to: linear, settings: textured), context: engine.context)
                try assertFiniteInRange(film, "\(source.lastPathComponent) \(wb)")

                let m = try WhiteBalanceMatrix.fit(url: source, nativeSize: native, from: nil, to: wb, context: engine.context)
                XCTAssertTrue(m.allSatisfy(\.isFinite), "matrix \(wb)")
                let base = try decoder.decode(scale: scale)
                let viaMatrix = Pixels.floats(try engine.applyFilm(to: WhiteBalanceMatrix.apply(m, to: base), settings: textured), context: engine.context)
                try assertFiniteInRange(viaMatrix, "matrix \(source.lastPathComponent) \(wb)")

                let mean = channelMeans(Pixels.floats(linear, context: engine.context))
                blueOverRed.append(mean.b / max(mean.r, 1e-6))
            }
            print("WB corners \(source.lastPathComponent) B/R: \(blueOverRed.map { String(format: "%.2f", $0) })")
            // Telling the decoder the light was 1800 K removes a lot of orange: the
            // image goes blue. At 50 000 K it goes orange.
            XCTAssertGreaterThan(blueOverRed[0], blueOverRed[2] * 2)
            XCTAssertGreaterThan(blueOverRed[1], blueOverRed[3] * 2)
        }
    }

    /// Values the page might send by mistake fall back or clamp instead of reaching the decoder.
    func testOddWhiteBalanceValuesFromThePageAreClamped() {
        let low = RawBridge.settings(from: ["wbTemp": -5.0, "wbTint": -9999.0])
        XCTAssertEqual(low.whiteBalance, WhiteBalance(temperature: 1800, tint: -150))
        let high = RawBridge.settings(from: ["wbTemp": 1e9, "wbTint": 9999.0])
        XCTAssertEqual(high.whiteBalance, WhiteBalance(temperature: 50_000, tint: 150))
        let junk = RawBridge.settings(from: ["wbTemp": "warm", "wbTint": Double.nan])
        if let wb = junk.whiteBalance {
            XCTAssertTrue(wb.temperature.isFinite && wb.tint.isFinite)
            XCTAssertTrue((1800...50_000).contains(wb.temperature) && (-150...150).contains(wb.tint))
        }
    }

    // MARK: Bayer vs ProRAW

    /// ProRAW is already demosaiced (LinearRaw) and Apple may bake in some processing;
    /// a Bayer DNG is raw sensor data. Both must decode scene-linear (+1 EV doubles),
    /// and the film look must treat the two the same way once decoded.
    func testBayerAndProRAWAreBothSceneLinear() throws {
        for source in [TestData.proRAW, TestData.bayer] {
            let decoder = RawDecoder(url: source)
            let a = Pixels.floats(try decoder.decode(scale: 0.05, exposure: 0), context: engine.context)
            let b = Pixels.floats(try decoder.decode(scale: 0.05, exposure: 1), context: engine.context)
            var ratios: [Float] = []
            for i in stride(from: 1, to: a.count, by: 4) where a[i] > 0.02 && a[i] < 0.4 { ratios.append(b[i] / a[i]) }
            XCTAssertGreaterThan(ratios.count, 100)
            let median = ratios.sorted()[ratios.count / 2]
            print("LINEARITY \(source.lastPathComponent) median ratio +1EV: \(median) over \(ratios.count) px")
            XCTAssertEqual(median, 2, accuracy: 0.05)
        }
    }

    /// The Apple rendering options we switch off are only supported on some files.
    /// Record which, and check the filter really holds the values we set.
    func testRenderingOptionsAreOffOnBothFileTypes() throws {
        for source in [TestData.proRAW, TestData.bayer] {
            let f = try RawDecoder(url: source).makeFilter(scale: 0.1, exposure: 0, whiteBalance: nil)
            print("OPTIONS \(source.lastPathComponent): localToneMap \(f.isLocalToneMapSupported), contrast \(f.isContrastSupported), sharpness \(f.isSharpnessSupported), detail \(f.isDetailSupported)")
            XCTAssertEqual(f.boostAmount, 0)
            XCTAssertEqual(f.boostShadowAmount, 0)
            if f.isLocalToneMapSupported { XCTAssertEqual(f.localToneMapAmount, 0) }
            if f.isContrastSupported { XCTAssertEqual(f.contrastAmount, 0) }
            if f.isSharpnessSupported { XCTAssertEqual(f.sharpnessAmount, 0) }
        }
    }

    // MARK: Helpers

    private func atOrigin(_ image: CIImage) -> CIImage {
        image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
    }

    private func assertFiniteInRange(_ px: [Float], _ label: String, file: StaticString = #filePath, line: UInt = #line) throws {
        var bad = 0
        for i in 0..<px.count where i % 4 != 3 {
            let v = px[i]
            if !v.isFinite || v < -1e-4 || v > 1.0001 { bad += 1 }
        }
        XCTAssertEqual(bad, 0, "non-finite or out-of-range film output: \(label)", file: file, line: line)
    }

    private func channelMeans(_ px: [Float]) -> (r: Float, g: Float, b: Float) {
        var r: Double = 0, g: Double = 0, b: Double = 0, n = 0.0
        for i in stride(from: 0, to: px.count, by: 4) where px[i].isFinite && px[i + 1].isFinite && px[i + 2].isFinite {
            r += Double(px[i]); g += Double(px[i + 1]); b += Double(px[i + 2]); n += 1
        }
        return (Float(r / n), Float(g / n), Float(b / n))
    }
}
