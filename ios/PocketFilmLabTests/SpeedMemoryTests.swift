import CoreImage
import XCTest
@testable import PocketFilmLab

/// Preview speed and memory: white balance drags and the 47 MP preview path.
final class SpeedMemoryTests: XCTestCase {
    let engine = FilmEngine()

    /// A WB change on the preview: the fitted matrix vs a true re-decode. Measures the
    /// latency of both and how far the matrix preview is from the true render (sRGB codes,
    /// after the film look).
    func testWhiteBalanceMatrixPreview() throws {
        var s = FilmSettings()
        for source in [TestData.proRAW, TestData.bayer] {
            let fast = try RawSession(url: source, engine: engine)
            let slow = try RawSession(url: source, engine: engine, fastWhiteBalance: false)
            _ = try fast.previewJPEG(settings: s, maxEdge: 1600, compare: false) // as-shot decode, cached
            _ = try slow.previewJPEG(settings: s, maxEdge: 1600, compare: false)
            let shot = fast.asShot
            for (dt, dTint) in [(Float(-1200), Float(0)), (1500, 10), (600, -15)] {
                s.whiteBalance = WhiteBalance(temperature: shot.temperature + dt, tint: shot.tint + dTint)
                let t0 = Date()
                _ = try fast.previewJPEG(settings: s, maxEdge: 1600, compare: false)
                let fastMs = Date().timeIntervalSince(t0) * 1000
                let t1 = Date()
                _ = try slow.previewJPEG(settings: s, maxEdge: 1600, compare: false)
                let slowMs = Date().timeIntervalSince(t1) * 1000

                // Accuracy: film renders at 800 px from the matrix path vs a true decode.
                let base = try RawDecoder(url: source).decode(scale: Float(800 / max(fast.nativeSize.width, fast.nativeSize.height)), whiteBalance: nil)
                let m = try WhiteBalanceMatrix.fit(url: source, nativeSize: fast.nativeSize, from: nil, to: s.whiteBalance, context: engine.context)
                let viaMatrix = try engine.applyFilm(to: WhiteBalanceMatrix.apply(m, to: base), settings: s)
                let truth = try engine.applyFilm(to: try RawDecoder(url: source).decode(scale: Float(800 / max(fast.nativeSize.width, fast.nativeSize.height)), whiteBalance: s.whiteBalance), settings: s)
                let a = Pixels.bytes(viaMatrix, context: engine.context), b = Pixels.bytes(truth, context: engine.context)
                var sum = 0, over6 = 0, n = 0
                for i in 0..<min(a.count, b.count) where i % 4 != 3 {
                    let d = abs(Int(a[i]) - Int(b[i])); sum += d; n += 1; if d > 6 { over6 += 1 }
                }
                let mean = Double(sum) / Double(n), frac = Double(over6) / Double(n)
                print(String(format: "WB %@ dT %+.0f dTint %+.0f: matrix %.0f ms, re-decode %.0f ms; preview error mean %.2f codes, >6 codes %.3f%%",
                             source.lastPathComponent, dt, dTint, fastMs, slowMs, mean, frac * 100))
                XCTAssertLessThan(mean, 2.5, "matrix WB preview drifts from the true decode")
                XCTAssertLessThan(frac, 0.03)
            }
        }
    }

    /// With the fitter pre-warmed (as the bridge does after the first preview), the
    /// first WB change costs the same as later ones.
    func testPrewarmedFirstWhiteBalanceChange() throws {
        var cold: [Double] = [], warm: [Double] = []
        for prewarm in [false, true] {
            for _ in 0..<2 {
                let session = try RawSession(url: TestData.proRAW, engine: engine)
                var s = FilmSettings()
                _ = try session.previewJPEG(settings: s, maxEdge: 1600, compare: false)
                if prewarm {
                    try session.prepareWhiteBalance()
                    XCTAssertTrue(session.isWhiteBalanceReady)
                }
                s.whiteBalance = WhiteBalance(temperature: session.asShot.temperature + 800, tint: session.asShot.tint)
                let t0 = Date()
                _ = try session.previewJPEG(settings: s, maxEdge: 1600, compare: false)
                let ms = Date().timeIntervalSince(t0) * 1000
                if prewarm { warm.append(ms) } else { cold.append(ms) }
            }
        }
        print(String(format: "WB first change: cold %.0f / %.0f ms, pre-warmed %.0f / %.0f ms", cold[0], cold[1], warm[0], warm[1]))
        XCTAssertLessThan(warm.min()!, cold.min()!)
    }

    /// 47 MP: open, first preview (reduced decode) and slider moves, with memory.
    func testLargeFilePreviewPath() throws {
        let start = physFootprint()
        var peak = start
        let timer = DispatchSource.makeTimerSource(queue: .global())
        timer.schedule(deadline: .now(), repeating: .milliseconds(10))
        timer.setEventHandler { peak = max(peak, physFootprint()) }
        timer.resume()
        let t0 = Date()
        let session = try RawSession(url: TestData.large47MP, engine: engine)
        let openMs = Date().timeIntervalSince(t0) * 1000
        var s = FilmSettings(); s.grain = 0.35; s.halation = 0.3
        let t1 = Date()
        _ = try session.previewJPEG(settings: s, maxEdge: 1600, compare: false)
        let firstMs = Date().timeIntervalSince(t1) * 1000
        var moves: [Double] = []
        for i in 1...6 {
            s.exposure = Float(i) * 0.1
            let t = Date()
            _ = try session.previewJPEG(settings: s, maxEdge: 1600, compare: false)
            moves.append(Date().timeIntervalSince(t) * 1000)
        }
        s.whiteBalance = WhiteBalance(temperature: session.asShot.temperature + 800, tint: session.asShot.tint)
        let t2 = Date()
        _ = try session.previewJPEG(settings: s, maxEdge: 1600, compare: false)
        let wbMs = Date().timeIntervalSince(t2) * 1000
        timer.cancel()
        let mb = Double(peak - start) / 1_048_576
        moves.sort()
        print(String(format: "LARGE 47MP preview: open %.0f ms, first preview %.0f ms, slider median %.0f ms max %.0f ms, WB %.0f ms, peak +%.0f MB",
                     openMs, firstMs, moves[moves.count / 2], moves.last!, wbMs, mb))
        XCTAssertLessThan(mb, 400, "the preview path must not decode full size")
        XCTAssertLessThan(moves[moves.count / 2], 500)
    }
}
