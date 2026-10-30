import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A picked photo that is not RAW goes to the web page's existing JPEG/PNG path.
/// JPEG and PNG bytes pass through unchanged (the page re-encodes on export and keeps
/// no metadata). Anything else Core Image reads (HEIC, TIFF, ...) becomes a JPEG with
/// the orientation applied and no metadata, because not every web view decodes HEIC.
enum FallbackImage {
    enum Failure: Error, LocalizedError {
        case unreadable(String)
        var errorDescription: String? {
            switch self {
            case .unreadable(let name): return "Could not read \(name) as a photo. Pick a RAW, JPEG, PNG or HEIC file."
            }
        }
    }

    static func isRaw(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .rawImage) ?? false
    }

    /// A file the page can load, plus the name it should see. JPEG and PNG are served as
    /// they are; anything else is written once as a JPEG next to `url` (our temp copy).
    static func servable(_ url: URL, context: CIContext) throws -> (file: URL, name: String) {
        if let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .jpeg) || type.conforms(to: .png) {
            guard CGImageSourceCreateWithURL(url as CFURL, nil).map(CGImageSourceGetCount) ?? 0 > 0 else {
                throw Failure.unreadable(url.lastPathComponent)
            }
            return (url, url.lastPathComponent)
        }
        let (data, name) = try prepare(url, context: context)
        let out = url.deletingLastPathComponent().appendingPathComponent("served-\(UUID().uuidString.prefix(6)).jpg")
        try data.write(to: out)
        return (out, name)
    }

    /// Bytes for the page plus the file name it should see.
    static func prepare(_ url: URL, context: CIContext) throws -> (data: Data, name: String) {
        let type = UTType(filenameExtension: url.pathExtension)
        if let type, type.conforms(to: .jpeg) || type.conforms(to: .png) {
            return (try Data(contentsOf: url), url.lastPathComponent)
        }
        guard let image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else {
            throw Failure.unreadable(url.lastPathComponent)
        }
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let jpeg = context.jpegRepresentation(
            of: image.settingProperties([:]), colorSpace: sRGB,
            options: [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.95]
        ) else { throw Failure.unreadable(url.lastPathComponent) }
        let name = url.deletingPathExtension().lastPathComponent + ".jpg"
        return (jpeg, name)
    }
}
