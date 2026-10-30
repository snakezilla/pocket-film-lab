import CoreImage
import Foundation

/// One opened RAW file. Keeps a reduced-size scene-linear decode in memory so
/// slider changes only re-run the film look, not the RAW decode.
final class RawSession {
    let url: URL
    let asShot: WhiteBalance
    let nativeSize: CGSize
    private let engine: FilmEngine
    private var cached: (wb: WhiteBalance?, edge: CGFloat, image: CIImage)?

    init(url: URL, engine: FilmEngine) throws {
        self.url = url
        self.engine = engine
        let decoder = RawDecoder(url: url)
        asShot = try decoder.asShotWhiteBalance()
        nativeSize = try decoder.nativeSize()
    }

    /// Scene-linear preview decode, rendered once per white balance into a half-float buffer.
    private func linearPreview(wb: WhiteBalance?, maxEdge: CGFloat) throws -> CIImage {
        if let c = cached, c.wb == wb, c.edge == maxEdge { return c.image }
        let longEdge = max(nativeSize.width, nativeSize.height)
        let scale = Float(min(1, maxEdge / longEdge))
        let lazy = try RawDecoder(url: url).decode(scale: scale, whiteBalance: wb)
        let extent = lazy.extent.integral
        let rowBytes = Int(extent.width) * 8
        var data = Data(count: rowBytes * Int(extent.height))
        let linear = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
        data.withUnsafeMutableBytes { buf in
            engine.context.render(lazy, toBitmap: buf.baseAddress!, rowBytes: rowBytes,
                                  bounds: extent, format: .RGBAh, colorSpace: linear)
        }
        let image = CIImage(bitmapData: data, bytesPerRow: rowBytes, size: extent.size,
                            format: .RGBAh, colorSpace: linear)
        cached = (wb, maxEdge, image)
        return image
    }

    /// JPEG preview. `compare` gives the plain decode (no film look) for hold-to-compare.
    func previewJPEG(settings: FilmSettings, maxEdge: CGFloat, compare: Bool) throws -> Data {
        let linear = engine.applyExposure(try linearPreview(wb: settings.whiteBalance, maxEdge: maxEdge), ev: settings.exposure)
        let image = compare ? linear : try engine.applyFilm(to: linear, settings: settings)
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let jpeg = engine.context.jpegRepresentation(
            of: image, colorSpace: sRGB,
            options: [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.85]
        ) else { throw FilmKernelError.applyFailed }
        return jpeg
    }

    /// Full-size render to a new temp file. The caller deletes it after sharing.
    func export(settings: FilmSettings, format: FilmExportFormat) throws -> URL {
        let linear = engine.applyExposure(try RawDecoder(url: url).decode(whiteBalance: settings.whiteBalance), ev: settings.exposure)
        let image = try engine.applyFilm(to: linear, settings: settings)
        let stamp = Int(Date().timeIntervalSince1970)
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("film-\(stamp)-\(UUID().uuidString.prefix(4)).\(format.fileExtension)")
        try FilmExporter(context: engine.context, quality: 0.95).write(image, format: format, to: out)
        return out
    }
}
