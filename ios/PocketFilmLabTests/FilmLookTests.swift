import CoreImage
import XCTest
@testable import PocketFilmLab

/// The film cube on synthetic scene-linear input.
final class FilmLookTests: XCTestCase {
    let engine = FilmEngine()

    /// One pixel per stop from -8 to +6 around mid grey (0.18).
    private func greyStops() -> (stops: [Int], image: CIImage) {
        let stops = Array(-8...6)
        let images = stops.enumerated().map { i, stop -> CIImage in
            let v = CGFloat(0.18 * pow(2.0, Double(stop)))
            return CIImage(color: CIColor(red: v, green: v, blue: v, colorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!)!)
                .cropped(to: CGRect(x: i, y: 0, width: 1, height: 1))
        }
        let strip = images.reduce(CIImage.empty()) { $1.composited(over: $0) }
        return (stops, strip)
    }

    func testLUTLoads() throws {
        let lut = try engine.lut(FilmEngine.defaultLookID)
        XCTAssertEqual(lut.meta.size, 65)
        XCTAssertTrue(lut.meta.print.contains("2383"), lut.meta.print)
    }

    func testGreysStayNeutral() throws {
        let (stops, strip) = greyStops()
        let out = try engine.applyFilm(to: strip, settings: FilmSettings())
        let px = Pixels.floats(out, context: engine.context)
        for (i, stop) in stops.enumerated() {
            let r = px[i * 4], g = px[i * 4 + 1], b = px[i * 4 + 2]
            assertNeutral(r, g, b, "stop \(stop)")
        }
    }

    /// Optional warmth: greys up to +1 stop untouched, near-whites cream (R > G > B,
    /// about b* +9 at +4 stops), and 0 gives back the neutral render exactly.
    func testWarmthIsOptionalAndOnlyWarmsHighlights() throws {
        let (stops, strip) = greyStops()
        var warm = FilmSettings(); warm.warmth = 1
        let a = Pixels.floats(try engine.applyFilm(to: strip, settings: FilmSettings()), context: engine.context)
        let b = Pixels.floats(try engine.applyFilm(to: strip, settings: warm), context: engine.context)
        for (i, stop) in stops.enumerated() {
            let (r, g, bl) = (b[i * 4], b[i * 4 + 1], b[i * 4 + 2])
            if stop <= 1 {
                XCTAssertEqual(r, a[i * 4], accuracy: 1e-4); XCTAssertEqual(bl, a[i * 4 + 2], accuracy: 1e-4)
            } else if stop >= 3 {
                XCTAssertGreaterThan(r, g, "stop \(stop)"); XCTAssertGreaterThan(g, bl, "stop \(stop)")
                XCTAssertGreaterThan(bl / g, 0.8); XCTAssertLessThan(r / g, 1.05)
            }
        }
        XCTAssertTrue(try FilmLookKernel.warm(strip, amount: 0) === strip)
    }

    /// Tone curve on the grey axis, printed for the record (measurements/RAW-TONE.md).
    func testHighlightRollOffIsMonotonicAndSoft() throws {
        let (stops, strip) = greyStops()
        let out = try engine.applyFilm(to: strip, settings: FilmSettings())
        let px = Pixels.floats(out, context: engine.context)
        let g = stops.indices.map { px[$0 * 4 + 1] }
        var report = "stop,in_linear,out_linear,out_srgb8\n"
        for (i, stop) in stops.enumerated() {
            let srgb = g[i] <= 0.0031308 ? 12.92 * g[i] : 1.055 * pow(g[i], 1 / 2.4) - 0.055
            report += "\(stop),\(0.18 * pow(2, Float(stop))),\(g[i]),\(Int((srgb * 255).rounded()))\n"
        }
        print("RAW-TONE\n" + report)
        for i in 1..<g.count { XCTAssertGreaterThan(g[i], g[i - 1], "not monotonic at stop \(stops[i])") }
        // Same curve as the Python film model (tools/make_raw_lut.py writes it to the LUT json).
        // Catches a quantised cube: 8-bit storage put stops -8...-4 at exactly 0.
        let expected = try pythonGreyRamp()
        for (i, stop) in stops.enumerated() {
            let want = expected[stop]!
            XCTAssertEqual(g[i], want, accuracy: max(0.01 * want, 2e-5), "stop \(stop) differs from the film model")
        }
        let mid = g[stops.firstIndex(of: 0)!]
        XCTAssertEqual(mid, 0.185, accuracy: 0.02, "mid grey moved")
        // Shoulder: each stop above +2 adds less than the one before, and +6 stops is not clipped.
        let top = stops.firstIndex(of: 6)!
        XCTAssertLessThan(g[top], 0.98)
        for i in stops.firstIndex(of: 3)!...top {
            XCTAssertLessThan(g[i] - g[i - 1], g[i - 1] - g[i - 2] + 1e-4, "shoulder not rolling off at stop \(stops[i])")
        }
    }

    private func pythonGreyRamp() throws -> [Int: Float] {
        struct Meta: Decodable { let greyRampStops: [Int]; let greyRampOutLinear: [[Float]] }
        let url = try XCTUnwrap(Bundle.main.url(forResource: FilmEngine.defaultLookID, withExtension: "json"))
        let meta = try JSONDecoder().decode(Meta.self, from: Data(contentsOf: url))
        return Dictionary(uniqueKeysWithValues: zip(meta.greyRampStops, meta.greyRampOutLinear.map { $0[1] }))
    }

    func testStrengthZeroIsThePlainDecode() throws {
        let (_, strip) = greyStops()
        var settings = FilmSettings()
        settings.strength = 0
        let out = Pixels.floats(try engine.applyFilm(to: strip, settings: settings), context: engine.context)
        let input = Pixels.floats(strip, context: engine.context)
        for i in stride(from: 0, to: input.count, by: 4) {
            XCTAssertEqual(out[i + 1], input[i + 1], accuracy: max(0.002 * input[i + 1], 1e-4))
        }
    }

    func testFilmChangesColourNotOnlyTone() throws {
        // A saturated scene-linear green should come out with a different hue ratio than it went in.
        let cs = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
        let green = CIImage(color: CIColor(red: 0.05, green: 0.25, blue: 0.04, colorSpace: cs)!)
            .cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1))
        let out = Pixels.floats(try engine.applyFilm(to: green, settings: FilmSettings()), context: engine.context)
        let inRatio: Float = 0.05 / 0.25, outRatio = out[0] / out[1]
        XCTAssertGreaterThan(abs(outRatio - inRatio), 0.01, "film cube looks tone-only: \(out[0...2])")
    }
}

/// Greys stay neutral within 1% per channel (or 0.0005 in deep shadow) at every stop.
/// This is the baseline; warm highlights are an optional setting (`warmth`, default 0).
func assertNeutral(_ r: Float, _ g: Float, _ b: Float, _ label: String, file: StaticString = #filePath, line: UInt = #line) {
    let spread = max(r, g, b) - min(r, g, b)
    XCTAssertLessThan(spread, max(0.01 * g, 0.0005), "\(label): \(r) \(g) \(b)", file: file, line: line)
}
