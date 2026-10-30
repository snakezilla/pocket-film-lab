import CoreImage
import Foundation

/// User-facing controls. Phase 1 covers look, strength, exposure and white balance.
struct FilmSettings: Equatable {
    var lookID = FilmEngine.defaultLookID
    var strength: Float = 1
    var exposure: Float = 0
    var whiteBalance: WhiteBalance? = nil
}

/// RAW -> scene-linear -> log shaper -> film cube -> display-linear.
/// Everything stays in Core Image so large images render in tiles on the GPU.
final class FilmEngine {
    static let defaultLookID = "vision3-250d-2383"

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

    /// Film look on a scene-linear image.
    func applyFilm(to linear: CIImage, settings: FilmSettings) throws -> CIImage {
        let look = try lut(settings.lookID)
        let film = try FilmLookKernel.apply(linear, cube: cubeImage(for: look), lut: look)
        let strength = min(max(settings.strength, 0), 1)
        if strength >= 1 { return film }
        // Mix in linear light. At 0 this is the plain linear decode, clipped on output.
        return film.applyingFilter("CIDissolveTransition", parameters: [
            "inputTargetImage": linear,
            "inputTime": 1 - strength,
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
