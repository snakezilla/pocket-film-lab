import CoreImage
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import PocketFilmLab

/// Export privacy (no source metadata at all) and the JPEG/PNG/HEIC fallback.
final class ExportPrivacyTests: XCTestCase {
    let engine = FilmEngine()

    /// Keys an export may carry: pixel geometry, colour profile and container basics only.
    static let allowedTop: Set<String> = [
        "ColorModel", "Depth", "PixelWidth", "PixelHeight", "ProfileName", "HasAlpha", "PrimaryImage",
        "FileSize", "Orientation", "DPIWidth", "DPIHeight", "Labels", "Headroom", "{JFIF}", "{Exif}", "{TIFF}", "{HEIF}",
    ]
    /// The encoders' own fixed defaults; none of them comes from the source file.
    static let allowedExif: Set<String> = [
        "PixelXDimension", "PixelYDimension", "ColorSpace", "ExifVersion", "FlashPixVersion",
        "ComponentsConfiguration", "SceneCaptureType",
    ]
    static let allowedTIFF: Set<String> = ["Orientation", "ResolutionUnit", "XResolution", "YResolution", "TileWidth", "TileLength"]

    /// Every export of every sample: only allowed keys, upright orientation, and no camera
    /// make/model or GPS text anywhere in the file bytes.
    func testExportsCarryNoSourceMetadata() throws {
        for source in [TestData.proRAW, TestData.bayer] {
            let make = (Pixels.properties(source)[kCGImagePropertyTIFFDictionary as String] as? [String: Any])?[kCGImagePropertyTIFFMake as String] as? String
            XCTAssertNotNil(make, "sample should have a camera make to leak")
            var s = FilmSettings(); s.grain = 0.35; s.halation = 0.3
            let session = try RawSession(url: source, engine: engine)
            for format in FilmExportFormat.allCases {
                let url = try session.export(settings: s, format: format)
                defer { try? FileManager.default.removeItem(at: url) }
                let props = Pixels.properties(url)
                let extra = Set(props.keys).subtracting(Self.allowedTop)
                XCTAssertTrue(extra.isEmpty, "\(format) extra keys \(extra)")
                let exif = Set((props["{Exif}"] as? [String: Any] ?? [:]).keys).subtracting(Self.allowedExif)
                XCTAssertTrue(exif.isEmpty, "\(format) extra Exif \(exif)")
                let tiff = Set((props["{TIFF}"] as? [String: Any] ?? [:]).keys).subtracting(Self.allowedTIFF)
                XCTAssertTrue(tiff.isEmpty, "\(format) extra TIFF \(tiff)")
                XCTAssertEqual(props["Orientation"] as? Int ?? 1, 1, "pixels must be upright")
                let bytes = try Data(contentsOf: url)
                for needle in [make!, "GPS", "MakerApple", "DateTimeOriginal"] {
                    XCTAssertNil(bytes.range(of: Data(needle.utf8)), "\(format) contains \(needle)")
                }
                print("PRIVACY \(source.lastPathComponent) \(format): keys \(props.keys.sorted()) \(bytes.count / 1024) KB")
            }
        }
    }

    func testRawIsRecognisedByType() {
        XCTAssertTrue(FallbackImage.isRaw(TestData.proRAW))
        XCTAssertFalse(FallbackImage.isRaw(URL(fileURLWithPath: "/x/a.jpg")))
        XCTAssertFalse(FallbackImage.isRaw(URL(fileURLWithPath: "/x/a.HEIC")))
    }

    /// JPEG and PNG pass through byte for byte (the page re-encodes them on export).
    func testJpegAndPngPassThrough() throws {
        for type in [UTType.jpeg, UTType.png] {
            let url = try Self.writeSample(type: type, orientation: 1, gps: false)
            defer { try? FileManager.default.removeItem(at: url) }
            let out = try FallbackImage.prepare(url, context: engine.context)
            XCTAssertEqual(out.data, try Data(contentsOf: url))
            XCTAssertEqual(out.name, url.lastPathComponent)
        }
    }

    /// HEIC becomes an upright JPEG with no GPS (orientation 6 = rotate 90 degrees).
    func testHeicIsTranscodedUprightWithoutMetadata() throws {
        let url = try Self.writeSample(type: .heic, orientation: 6, gps: true)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertNotNil(Pixels.properties(url)[kCGImagePropertyGPSDictionary as String], "fixture has GPS")
        let out = try FallbackImage.prepare(url, context: engine.context)
        XCTAssertTrue(out.name.hasSuffix(".jpg"))
        let jpg = tempURL("fallback.jpg")
        try out.data.write(to: jpg)
        defer { try? FileManager.default.removeItem(at: jpg) }
        let props = Pixels.properties(jpg)
        XCTAssertNil(props[kCGImagePropertyGPSDictionary as String])
        XCTAssertEqual(props["Orientation"] as? Int ?? 1, 1)
        XCTAssertEqual(props[kCGImagePropertyPixelWidth as String] as? Int, 60, "rotated: 120x60 -> 60x120")
        XCTAssertEqual(props[kCGImagePropertyPixelHeight as String] as? Int, 120)
    }

    func testUnreadableFileFailsClearly() throws {
        let url = tempURL("broken.heic")
        try Data("not an image".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertThrowsError(try FallbackImage.prepare(url, context: engine.context))
    }

    /// 120x60 test photo with optional EXIF orientation and GPS.
    static func writeSample(type: UTType, orientation: Int, gps: Bool) throws -> URL {
        let url = tempURL("sample.\(type.preferredFilenameExtension ?? "img")")
        let ctx = CGContext(data: nil, width: 120, height: 60, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.setFillColor(red: 0.8, green: 0.4, blue: 0.2, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: 120, height: 60))
        let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)!
        var props: [String: Any] = [kCGImagePropertyOrientation as String: orientation]
        if gps {
            props[kCGImagePropertyGPSDictionary as String] = [kCGImagePropertyGPSLatitude as String: 45.5, kCGImagePropertyGPSLatitudeRef as String: "N"]
        }
        CGImageDestinationAddImage(dest, ctx.makeImage()!, props as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return url
    }
}
