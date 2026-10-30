import CoreImage
import XCTest
@testable import PocketFilmLab

/// All three looks, halation and density-weighted grain on synthetic scene-linear input.
final class TextureTests: XCTestCase {
    let engine = FilmEngine()
    let linear = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!

    private func flat(_ v: CGFloat, size: CGFloat = 512) -> CIImage {
        CIImage(color: CIColor(red: v, green: v, blue: v, colorSpace: linear)!)
            .cropped(to: CGRect(x: 0, y: 0, width: size, height: size))
    }

    private func meanStd(_ px: [Float], channel: Int) -> (Float, Float) {
        let vals = stride(from: channel, to: px.count, by: 4).map { px[$0] }
        let mean = vals.reduce(0, +) / Float(vals.count)
        let variance = vals.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Float(vals.count)
        return (mean, variance.squareRoot())
    }

    func testAllLooksLoadAndKeepGreysNeutral() throws {
        for id in FilmEngine.lookIDs {
            let lut = try engine.lut(id)
            XCTAssertTrue(lut.meta.print.contains("2383"), "\(id): \(lut.meta.print)")
            for stop in [-4.0, -1, 0, 2, 5] {
                let v = CGFloat(0.18 * pow(2, stop))
                var s = FilmSettings(); s.lookID = id
                let out = try engine.applyFilm(to: flat(v, size: 4), settings: s)
                let px = Pixels.floats(out, context: engine.context)
                assertNeutral(px[0], px[1], px[2], "\(id) stop \(stop)")
            }
        }
    }

    func testLooksDifferOnColour() throws {
        let skin = CIImage(color: CIColor(red: 0.42, green: 0.22, blue: 0.14, colorSpace: linear)!)
            .cropped(to: CGRect(x: 0, y: 0, width: 2, height: 2))
        var outs: [[Float]] = []
        for id in FilmEngine.lookIDs {
            var s = FilmSettings(); s.lookID = id
            outs.append(Array(Pixels.floats(try engine.applyFilm(to: skin, settings: s), context: engine.context)[0..<3]))
            print("LOOK \(id) skin(0.42,0.22,0.14) ->", outs.last!)
        }
        for i in 1..<outs.count {
            let d = zip(outs[0], outs[i]).map { abs($0 - $1) }.max()!
            XCTAssertGreaterThan(d, 0.003, "look \(FilmEngine.lookIDs[i]) is identical to 250D")
        }
    }

    /// Grain follows print density: none on paper white, most around mid grey, less in deep black.
    /// At the UI default (0.35) on a 3000 px wide render: LOOK-TRAITS targets ~4 codes
    /// at midtones, ~3 above code 200, ~1.5 near black.
    func testGrainIsDensityWeighted() throws {
        var s = FilmSettings(); s.grain = 0.35
        func flat(_ v: CGFloat) -> CIImage {
            CIImage(color: CIColor(red: v, green: v, blue: v, colorSpace: linear)!)
                .cropped(to: CGRect(x: 0, y: 0, width: 3000, height: 96))
        }
        var results: [(stop: Double, std: Float, mean: Float, cleanMean: Float)] = []
        for stop in [-6.0, -3, -1, 0, 2, 7] {
            let v = CGFloat(0.18 * pow(2, stop))
            var clean = s; clean.grain = 0
            let grained = Pixels.bytes(try engine.applyFilm(to: flat(v), settings: s), context: engine.context)
            let plain = Pixels.bytes(try engine.applyFilm(to: flat(v), settings: clean), context: engine.context)
            let g = grained.map(Float.init), p = plain.map(Float.init)
            let (m, sd) = meanStd(g, channel: 1)
            let (pm, _) = meanStd(p, channel: 1)
            results.append((stop, sd, m, pm))
            print(String(format: "GRAIN stop %+.0f: sRGB mean %.1f (clean %.1f) std %.2f codes", stop, m, pm, sd))
        }
        let byStop = Dictionary(uniqueKeysWithValues: results.map { ($0.stop, $0) })
        XCTAssertGreaterThan(byStop[0]!.std, 2.5, "visible grain at mid grey")
        XCTAssertLessThan(byStop[0]!.std, 6.0, "grain at mid grey is not overwhelming")
        XCTAssertLessThan(byStop[-6]!.std, byStop[0]!.std, "less grain in deep black")
        XCTAssertLessThan(byStop[7]!.std, byStop[0]!.std, "less grain near paper white")
        for r in results { XCTAssertEqual(r.mean, r.cleanMean, accuracy: 2.0, "grain keeps mean at stop \(r.stop)") }
    }

    /// Smaller renders show less grain (same grain size relative to the frame, averaged).
    func testGrainScalesWithRenderSize() throws {
        var s = FilmSettings(); s.grain = 1
        let small = Pixels.bytes(try engine.applyFilm(to: flat(0.18, size: 600), settings: s), context: engine.context).map(Float.init)
        let big = Pixels.bytes(try engine.applyFilm(to: flat(0.18, size: 4000).cropped(to: CGRect(x: 0, y: 0, width: 4000, height: 300)), settings: s), context: engine.context).map(Float.init)
        let (_, sSmall) = meanStd(small, channel: 1)
        let (_, sBig) = meanStd(big, channel: 1)
        print(String(format: "GRAIN size: 600px std %.2f, 4000px std %.2f", sSmall, sBig))
        XCTAssertLessThan(sSmall, sBig)
    }

    /// Softness: off changes nothing; on lowers fine-detail contrast but keeps the mean
    /// level and greys neutral.
    func testSoftnessIsGentleAndOffByDefault() throws {
        XCTAssertEqual(FilmSettings().softness, 0)
        // Checkerboard of two greys, 4-px squares, on a 4000 px canvas (sigma ~2.8 px).
        let checker = CIFilter(name: "CICheckerboardGenerator", parameters: [
            "inputColor0": CIColor(red: 0.09, green: 0.09, blue: 0.09),
            "inputColor1": CIColor(red: 0.36, green: 0.36, blue: 0.36),
            "inputWidth": 4.0, "inputSharpness": 1.0,
        ])!.outputImage!.cropped(to: CGRect(x: 0, y: 0, width: 4000, height: 4000))
        XCTAssertTrue(FilmTexture.soften(checker, amount: 0) === checker)
        func contrast(_ img: CIImage) -> (std: Float, mean: Float, maxCast: Float) {
            let px = Pixels.floats(img.cropped(to: CGRect(x: 1000, y: 1000, width: 200, height: 200)), context: engine.context)
            var g: [Float] = []; var cast: Float = 0
            for i in stride(from: 0, to: px.count, by: 4) {
                g.append(px[i + 1]); cast = max(cast, abs(px[i] - px[i + 1]), abs(px[i + 2] - px[i + 1]))
            }
            let mean = g.reduce(0, +) / Float(g.count)
            let std = (g.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Float(g.count)).squareRoot()
            return (std, mean, cast)
        }
        let sharp = contrast(checker), soft = contrast(FilmTexture.soften(checker, amount: 1))
        print(String(format: "SOFTNESS 4-px checker std %.4f -> %.4f, mean %.4f -> %.4f", sharp.std, soft.std, sharp.mean, soft.mean))
        XCTAssertLessThan(soft.std, sharp.std * 0.8)
        XCTAssertGreaterThan(soft.std, sharp.std * 0.2, "gentle, not a full blur")
        XCTAssertEqual(soft.mean, sharp.mean, accuracy: 0.01)
        XCTAssertLessThan(soft.maxCast, 1e-3)
        // Bridge key round trip.
        XCTAssertEqual(RawBridge.settings(from: ["softness": 0.5]).softness, 0.5)
        XCTAssertEqual(RawBridge.settings(from: ["softness": 7.0]).softness, 1)
    }

    /// Halation: a bright spot gets a red-orange glow around it, mid tones far away are untouched.
    func testHalationIsRedOrangeAroundHighlights() throws {
        let size: CGFloat = 1000
        let bg = flat(0.09, size: size)
        let spot = CIImage(color: CIColor(red: 40, green: 40, blue: 40, colorSpace: linear)!)
            .cropped(to: CGRect(x: 490, y: 490, width: 20, height: 20))
        let scene = spot.composited(over: bg)
        var s = FilmSettings(); s.halation = 1
        var off = s; off.halation = 0
        let withHalo = Pixels.floats(try engine.applyFilm(to: scene, settings: s), context: engine.context)
        let without = Pixels.floats(try engine.applyFilm(to: scene, settings: off), context: engine.context)
        func at(_ px: [Float], _ x: Int, _ y: Int) -> [Float] {
            let i = (y * Int(size) + x) * 4
            return Array(px[i..<i + 3])
        }
        let near = at(withHalo, 500, 535), nearOff = at(without, 500, 535)
        let far = at(withHalo, 50, 50), farOff = at(without, 50, 50)
        print("HALO near on \(near) off \(nearOff); far on \(far) off \(farOff)")
        let dr = near[0] - nearOff[0], dg = near[1] - nearOff[1], db = near[2] - nearOff[2]
        XCTAssertGreaterThan(dr, 0.01, "red glow next to the highlight")
        XCTAssertGreaterThan(dr, dg * 1.5, "glow is red-dominant")
        XCTAssertGreaterThan(dg, db, "orange, not magenta")
        XCTAssertEqual(far[0], farOff[0], accuracy: 0.002, "mid tones far away untouched")
    }
}
