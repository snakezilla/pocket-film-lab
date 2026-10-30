import CoreImage
import Foundation

/// User-facing controls. Grain and halation default to 0 here so the bare engine is
/// a pure colour transform; the UI sends its own defaults.
struct FilmSettings: Equatable {
    var lookID = FilmEngine.defaultLookID
    var strength: Float = 1
    var exposure: Float = 0
    var whiteBalance: WhiteBalance? = nil
    /// 0...1
    var grain: Float = 0
    /// 0...1
    var halation: Float = 0
    /// 0...1. Gentle softening, off by default.
    var softness: Float = 0
    /// 0...1. Optional warm (cream) near-whites. 0 keeps greys neutral, the baseline.
    var warmth: Float = 0
    /// Shifts the grain field. Fixed by default so renders are repeatable.
    var grainSeed: CGFloat = 0
}

/// RAW -> scene-linear -> log shaper -> film cube -> display-linear.
/// Everything stays in Core Image so large images render in tiles on the GPU.
final class FilmEngine {
    static let defaultLookID = "vision3-250d-2383"
    /// Every look shipped in Resources/LUTs, in UI order.
    static let lookIDs = ["vision3-250d-2383", "vision3-500t-2383", "portra400-2383"]

    /// Linear working space with half floats: keeps scene values above 1.0 and
    /// deep shadows (down to about 6e-5) intact between filters.
    let context: CIContext
    private var luts: [String: FilmLUT] = [:]
    private var cubes: [String: CIImage] = [:]
    private let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
        let linear = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
        context = CIContext(options: [
            .workingColorSpace: linear,
            .workingFormat: CIFormat.RGBAh,
            .cacheIntermediates: false,
        ])
    }

    func lut(_ id: String) throws -> FilmLUT {
        if let cached = luts[id] { return cached }
        let loaded = try FilmLUT.load(id: id, bundle: bundle)
        luts[id] = loaded
        return loaded
    }

    private func cubeImage(for look: FilmLUT) -> CIImage {
        if let cached = cubes[look.meta.id] { return cached }
        let image = FilmLookKernel.cubeImage(look)
        cubes[look.meta.id] = image
        return image
    }

    /// Film look on a scene-linear image:
    /// softness + halation (scene-linear) -> negative + print cube -> strength mix -> grain (print density).
    func applyFilm(to linear: CIImage, settings: FilmSettings) throws -> CIImage {
        let look = try lut(settings.lookID)
        let softened = FilmTexture.soften(linear, amount: clamp01(settings.softness))
        let halated = try FilmTexture.halation(softened, amount: clamp01(settings.halation))
        let film = try FilmLookKernel.warm(
            try FilmLookKernel.apply(halated, cube: cubeImage(for: look), lut: look), amount: clamp01(settings.warmth))
        let strength = clamp01(settings.strength)
        // Mix in linear light. At 0 this is the plain linear decode, clipped on output.
        let mixed = strength >= 1 ? film : film.applyingFilter("CIDissolveTransition", parameters: [
            "inputTargetImage": linear,
            "inputTime": 1 - strength,
        ])
        return try FilmTexture.grain(mixed, amount: clamp01(settings.grain) * strength, seed: settings.grainSeed)
    }

    /// Exposure as a gain in linear light. Same result as CIRAWFilter's exposure for
    /// unclipped values, and lets the preview reuse one cached decode.
    func applyExposure(_ linear: CIImage, ev: Float) -> CIImage {
        guard ev != 0 else { return linear }
        let k = CGFloat(pow(2, ev))
        return linear.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: k, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: k, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: k, w: 0),
        ])
    }

    /// Decode and develop. `maxPixelSize` limits the long edge (preview); nil is full size (export).
    func render(raw url: URL, settings: FilmSettings, maxPixelSize: CGFloat? = nil) throws -> CIImage {
        let decoder = RawDecoder(url: url)
        var scale: Float = 1
        if let maxPixelSize {
            let size = try decoder.nativeSize()
            let longEdge = max(size.width, size.height)
            if longEdge > maxPixelSize { scale = Float(maxPixelSize / longEdge) }
        }
        let linear = try decoder.decode(scale: scale, exposure: settings.exposure, whiteBalance: settings.whiteBalance)
        return try applyFilm(to: linear, settings: settings)
    }
}

private func clamp01(_ v: Float) -> Float { v.isFinite ? min(max(v, 0), 1) : 0 }
