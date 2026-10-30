import CoreImage
import Foundation

/// Halation (scene-linear, before the film cube) and grain (print density, after it).
///
/// Sizes are fractions of the image's long edge, so a 1280 px preview and a
/// full-size export show the same texture at the same print size.
enum FilmTexture {
    /// Scene-linear level where halation starts: 2.5 stops over mid grey.
    static let halationThreshold: Float = 0.18 * 5.66
    /// Wide glow sigma as a fraction of the long edge. LOOK-TRAITS measured a decay
    /// over ~3-5% of the width (weak evidence, confounded by flare); 1.2% sigma
    /// fades out by ~4%.
    static let halationRadius: CGFloat = 0.012
    /// Glow added per unit of over-threshold light at halation = 1. Judged by eye:
    /// LOOK-TRAITS calls the reference halation subtle, with no saturated ring.
    static let halationGain: Float = 0.25
    /// Red-orange: mostly red layer, some green, almost no blue. Judged by eye.
    static let halationTint = CIVector(x: 1.0, y: 0.32, z: 0.06)
    /// Grain cell as a fraction of the long edge. LOOK-TRAITS measured ~0.0002-0.0004
    /// of the width (about 1 px at 2880 px), a lower bound; 1/3000 sits in that range.
    static let grainCell: CGFloat = 1.0 / 3000.0
    /// Density swing at grain = 1. Tuned so the UI default (0.35) gives ~4 sRGB codes
    /// of std at mid grey on a ~3000 px render, the LOOK-TRAITS midtone target.
    static let grainDensitySigma: Float = 0.55
    /// How much of the grain is independent per dye layer (0 = mono).
    static let grainChroma: Float = 0.35

    private static func load(_ name: String) -> Result<CIColorKernel, Error> {
        Result {
            guard let url = Bundle(for: TextureBundleToken.self).url(forResource: "default", withExtension: "metallib") else {
                throw FilmKernelError.missingLibrary
            }
            return try CIColorKernel(functionName: name, fromMetalLibraryData: Data(contentsOf: url))
        }
    }

    private static let sourceKernel = load("halationSource")
    private static let addKernel = load("halationAdd")
    private static let grainKernel = load("filmGrain")

    /// `amount` 0...1. Scene-linear in, scene-linear out.
    static func halation(_ image: CIImage, amount: Float) throws -> CIImage {
        guard amount > 0 else { return image }
        let extent = image.extent
        let longEdge = max(extent.width, extent.height)
        guard let source = try sourceKernel.get().apply(
            extent: extent, arguments: [image, halationThreshold]
        ) else { throw FilmKernelError.applyFailed }
        let radius = max(longEdge * halationRadius, 1)
        // Two blurs: a tight core and a wide skirt, like the falloff of a real halo.
        let tight = source.clampedToExtent().applyingGaussianBlur(sigma: Double(radius * 0.35)).cropped(to: extent)
        let wide = source.clampedToExtent().applyingGaussianBlur(sigma: Double(radius)).cropped(to: extent)
        let glow = tight.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: wide])
        guard let out = try addKernel.get().apply(
            extent: extent, arguments: [image, glow, amount * halationGain, halationTint]
        ) else { throw FilmKernelError.applyFailed }
        return out
    }

    /// `amount` 0...1. Display-linear in, display-linear out.
    /// `seed` shifts the noise field so two exports are not identical; tests pin it.
    static func grain(_ image: CIImage, amount: Float, seed: CGFloat = 0) throws -> CIImage {
        guard amount > 0 else { return image }
        let extent = image.extent
        let longEdge = max(extent.width, extent.height)
        let cell = longEdge * grainCell
        // Below one pixel per cell the grain averages out on screen, as it would
        // when a print is viewed small; the density swing shrinks with the cell size.
        let pixelCell = max(cell, 1)
        let visibility = Float(min(cell, 1))
        let fine = noise(cell: pixelCell, offset: seed, extent: extent)
        let coarse = noise(cell: pixelCell * 2.2, offset: seed + 977, extent: extent)
        let sigma = amount * grainDensitySigma * visibility
        guard let out = try grainKernel.get().apply(
            extent: extent, arguments: [image, fine, coarse, sigma, grainChroma]
        ) else { throw FilmKernelError.applyFailed }
        return out
    }

    /// Uniform noise (RGBA independent) with cells `cell` pixels wide, smoothly interpolated.
    private static func noise(cell: CGFloat, offset: CGFloat, extent: CGRect) -> CIImage {
        let random = CIFilter(name: "CIRandomGenerator")!.outputImage!
        return random
            .transformed(by: CGAffineTransform(translationX: offset, y: offset * 0.61))
            .transformed(by: CGAffineTransform(scaleX: cell, y: cell))
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
            .cropped(to: extent)
    }
}

private final class TextureBundleToken {}
