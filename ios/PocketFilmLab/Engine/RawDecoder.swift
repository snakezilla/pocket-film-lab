import CoreImage
import Foundation

enum RawDecodeError: Error, LocalizedError {
    case unsupported(URL)
    case noImage(URL)

    var errorDescription: String? {
        switch self {
        case .unsupported(let url): return "Not a RAW file Core Image can read: \(url.lastPathComponent)"
        case .noImage(let url): return "The RAW decoder returned no image for \(url.lastPathComponent)"
        }
    }
}

/// White balance in the units CIRAWFilter uses. `nil` keeps the file's as-shot value.
struct WhiteBalance: Equatable {
    var temperature: Float
    var tint: Float
}

/// Decodes ProRAW / DNG to scene-linear Rec.709 (Core Image's linear working space).
///
/// Every rendering step CIRAWFilter would add on top of the sensor data is turned
/// off: no boost tone curve, no local tone map, no sharpening or contrast. The
/// file's baseline exposure and as-shot white balance stay on, because they are
/// part of what the camera measured, not a look.
struct RawDecoder {
    let url: URL

    /// Native pixel size before any scaling (orientation not applied).
    func nativeSize() throws -> CGSize {
        try makeFilter(scale: 1, exposure: 0, whiteBalance: nil).nativeSize
    }

    /// As-shot white balance from the file.
    func asShotWhiteBalance() throws -> WhiteBalance {
        let filter = try makeFilter(scale: 1, exposure: 0, whiteBalance: nil)
        return WhiteBalance(temperature: filter.neutralTemperature, tint: filter.neutralTint)
    }

    /// Scene-linear image. `scale` < 1 decodes at reduced size (the preview path).
    func decode(scale: Float = 1, exposure: Float = 0, whiteBalance: WhiteBalance? = nil) throws -> CIImage {
        let filter = try makeFilter(scale: scale, exposure: exposure, whiteBalance: whiteBalance)
        guard let image = filter.outputImage else { throw RawDecodeError.noImage(url) }
        // Drop the source metadata (EXIF, GPS, maker notes) at the start so no
        // export path can carry it along.
        return image.settingProperties([:])
    }

    private func makeFilter(scale: Float, exposure: Float, whiteBalance: WhiteBalance?) throws -> CIRAWFilter {
        guard let filter = CIRAWFilter(imageURL: url) else { throw RawDecodeError.unsupported(url) }
        filter.scaleFactor = min(max(scale, 0.01), 1)
        filter.exposure = exposure
        filter.boostAmount = 0
        filter.boostShadowAmount = 0
        filter.shadowBias = 0
        filter.extendedDynamicRangeAmount = 0
        if filter.isLocalToneMapSupported { filter.localToneMapAmount = 0 }
        if filter.isContrastSupported { filter.contrastAmount = 0 }
        if filter.isSharpnessSupported { filter.sharpnessAmount = 0 }
        if filter.isDetailSupported { filter.detailAmount = 0 }
        if let wb = whiteBalance {
            filter.neutralTemperature = wb.temperature
            filter.neutralTint = wb.tint
        }
        return filter
    }
}
