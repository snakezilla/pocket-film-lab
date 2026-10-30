import CoreImage
import Foundation

enum FilmExportFormat: String, CaseIterable {
    case jpeg, heic

    var fileExtension: String { rawValue == "jpeg" ? "jpg" : "heic" }
}

enum FilmExportError: Error, LocalizedError {
    case writeFailed(FilmExportFormat, Error)
    var errorDescription: String? {
        switch self {
        case .writeFailed(let format, let error): return "Could not write \(format.rawValue): \(error.localizedDescription)"
        }
    }
}

/// Writes a developed image as 8-bit sRGB. The source file is only ever read.
/// No source metadata is written: RawDecoder strips it, and we pass none here.
struct FilmExporter {
    let context: CIContext
    var quality: CGFloat = 0.92

    func write(_ image: CIImage, format: FilmExportFormat, to url: URL) throws {
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
        let clean = image.settingProperties([:])
        let options: [CIImageRepresentationOption: Any] = [
            CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): quality,
        ]
        do {
            switch format {
            case .jpeg:
                try context.writeJPEGRepresentation(of: clean, to: url, colorSpace: sRGB, options: options)
            case .heic:
                try context.writeHEIFRepresentation(of: clean, to: url, format: .RGBA8, colorSpace: sRGB, options: options)
            }
        } catch {
            throw FilmExportError.writeFailed(format, error)
        }
    }
}
