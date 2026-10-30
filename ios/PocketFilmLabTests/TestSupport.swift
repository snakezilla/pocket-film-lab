import CoreImage
import Foundation
import ImageIO
@testable import PocketFilmLab

enum TestData {
    static let dir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("TestData")
    static let proRAW = dir.appendingPathComponent("iphone12pro-proraw.dng")
    static let bayer = dir.appendingPathComponent("iphonexs-bayer.dng")
    static let large47MP = dir.appendingPathComponent("leicaq2-47mp.dng")
}

/// Pixel readback helpers.
enum Pixels {
    /// Renders to float RGBA in the given colour space (linear by default).
    static func floats(_ image: CIImage, context: CIContext, space: CFString = CGColorSpace.extendedLinearSRGB) -> [Float] {
        let w = Int(image.extent.width), h = Int(image.extent.height)
        var out = [Float](repeating: 0, count: w * h * 4)
        out.withUnsafeMutableBytes { buf in
            context.render(image, toBitmap: buf.baseAddress!, rowBytes: w * 16,
                           bounds: image.extent, format: .RGBAf, colorSpace: CGColorSpace(name: space))
        }
        return out
    }

    /// Renders to 8-bit sRGB RGBA, the same encoding the exporter uses.
    static func bytes(_ image: CIImage, context: CIContext) -> [UInt8] {
        let w = Int(image.extent.width), h = Int(image.extent.height)
        var out = [UInt8](repeating: 0, count: w * h * 4)
        out.withUnsafeMutableBytes { buf in
            context.render(image, toBitmap: buf.baseAddress!, rowBytes: w * 4,
                           bounds: image.extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        }
        return out
    }

    /// Decodes an exported file to 8-bit sRGB RGBA with ImageIO (not Core Image).
    static func decodeFile(_ url: URL) -> (width: Int, height: Int, rgba: [UInt8])? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        let w = cg.width, h = cg.height
        var out = [UInt8](repeating: 0, count: w * h * 4)
        let ok = out.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return ok ? (w, h, out) : nil
    }

    static func properties(_ url: URL) -> [String: Any] {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return [:] }
        return CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any] ?? [:]
    }
}

/// Process memory footprint in bytes (what jetsam counts on iOS).
func physFootprint() -> UInt64 {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let kr = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return kr == KERN_SUCCESS ? info.phys_footprint : 0
}

func tempURL(_ name: String) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-" + name)
}
