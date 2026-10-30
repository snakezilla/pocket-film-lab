import CoreImage
import Foundation

enum FilmKernelError: Error, LocalizedError {
    case missingLibrary
    case applyFailed

    var errorDescription: String? {
        switch self {
        case .missingLibrary: return "The Core Image Metal library (default.metallib) is missing from the app"
        case .applyFailed: return "The film kernel could not be applied"
        }
    }
}

/// Wraps FilmLook.ci.metal: log shaper + trilinear float cube lookup.
enum FilmLookKernel {
    private static let kernel: Result<CIKernel, Error> = {
        Result {
            guard let url = Bundle(for: BundleToken.self).url(forResource: "default", withExtension: "metallib") else {
                throw FilmKernelError.missingLibrary
            }
            return try CIKernel(functionName: "filmLook", fromMetalLibraryData: Data(contentsOf: url))
        }
    }()

    private static let warmKernel: Result<CIColorKernel, Error> = {
        Result {
            guard let url = Bundle(for: BundleToken.self).url(forResource: "default", withExtension: "metallib") else {
                throw FilmKernelError.missingLibrary
            }
            return try CIColorKernel(functionName: "warmHighlights", fromMetalLibraryData: Data(contentsOf: url))
        }
    }()

    /// Warm highlight gains at warmth = 1 and the display-Y ramp (from make_raw_lut.py).
    static let warmGains = CIVector(x: 1.037, y: 1.0051, z: 0.84)
    static let warmRamp: (Float, Float) = (0.36, 0.64)

    /// Optional cream near-whites. `amount` 0 returns the input unchanged (neutral baseline).
    static func warm(_ image: CIImage, amount: Float) throws -> CIImage {
        guard amount > 0 else { return image }
        guard let out = try warmKernel.get().apply(
            extent: image.extent, arguments: [image, amount, warmGains, warmRamp.0, warmRamp.1]
        ) else { throw FilmKernelError.applyFailed }
        return out
    }

    /// The cube as a float image, `size` wide and `size * size` tall, no colour management.
    /// Core Image puts the first bitmap row at the top; the kernel wants row 0 at y = 0,
    /// so the image is flipped vertically (pixel-aligned, no resampling).
    static func cubeImage(_ lut: FilmLUT) -> CIImage {
        let size = lut.meta.size
        let height = CGFloat(size * size)
        return CIImage(
            bitmapData: lut.cubeData,
            bytesPerRow: size * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: size, height: size * size),
            format: .RGBAf,
            colorSpace: nil
        ).transformed(by: CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: height))
    }

    static func apply(_ image: CIImage, cube: CIImage, lut: FilmLUT) throws -> CIImage {
        let k = try kernel.get()
        let shaper = lut.meta.shaper
        let args: [Any] = [image, cube, Float(lut.meta.size), shaper.midGrey, shaper.logMin, shaper.logMax]
        let out = k.apply(extent: image.extent, roiCallback: { index, rect in
            index == 0 ? rect : cube.extent
        }, arguments: args)
        guard let out else { throw FilmKernelError.applyFailed }
        return out
    }
}

private final class BundleToken {}
