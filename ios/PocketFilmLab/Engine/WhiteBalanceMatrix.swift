import CoreImage
import Foundation

/// Preview-only white balance: a 3x3 matrix that maps a scene-linear decode made at
/// one white balance to (close to) the decode at another.
///
/// CIRAWFilter applies white balance in camera space, before its camera -> RGB matrix,
/// so in our linear RGB the change is a 3x3 matrix, not three gains. We fit that matrix
/// by least squares between two tiny decodes (about 160 px long edge), so a WB drag no
/// longer re-decodes the full preview. Export always does a true decode at the chosen
/// white balance.
enum WhiteBalanceMatrix {
    /// Long edge of the fitting decodes.
    static let fitEdge: CGFloat = 160

    /// Fits matrices for one file. Keeps one small CIRAWFilter alive (creating a filter
    /// parses the whole file, which is most of the cost of a decode) and the small decode
    /// at the base white balance, so each new WB costs one small render.
    final class Fitter {
        let base: WhiteBalance?
        private let filter: CIRAWFilter
        private let context: CIContext
        private let from: [Float]

        init(url: URL, nativeSize: CGSize, base: WhiteBalance?, context: CIContext) throws {
            let scale = Float(min(1, fitEdge / max(nativeSize.width, nativeSize.height)))
            self.base = base
            self.context = context
            filter = try RawDecoder(url: url).makeFilter(scale: scale, exposure: 0, whiteBalance: base)
            guard let image = filter.outputImage else { throw RawDecodeError.noImage(url) }
            from = WhiteBalanceMatrix.render(image, context: context)
        }

        /// Row-major 3x3 `m` such that decode(to) ≈ m · decode(base) per pixel.
        func matrix(to wb: WhiteBalance) throws -> [Float] {
            filter.neutralTemperature = wb.temperature
            filter.neutralTint = wb.tint
            guard let image = filter.outputImage else { throw FilmKernelError.applyFailed }
            return WhiteBalanceMatrix.solve(from: from, to: WhiteBalanceMatrix.render(image, context: context))
        }
    }

    /// One-off fit (tests): decode(to) ≈ m · decode(from).
    static func fit(url: URL, nativeSize: CGSize, from: WhiteBalance?, to: WhiteBalance?, context: CIContext) throws -> [Float] {
        let fitter = try Fitter(url: url, nativeSize: nativeSize, base: from, context: context)
        let target = try to ?? RawDecoder(url: url).asShotWhiteBalance()
        return try fitter.matrix(to: target)
    }

    /// The matrix as a Core Image filter.
    static func apply(_ m: [Float], to image: CIImage) -> CIImage {
        func row(_ r: Int) -> CIVector {
            CIVector(x: CGFloat(m[r * 3]), y: CGFloat(m[r * 3 + 1]), z: CGFloat(m[r * 3 + 2]), w: 0)
        }
        return image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": row(0), "inputGVector": row(1), "inputBVector": row(2),
        ])
    }

    /// Least squares over pixels that are well exposed in both decodes (no clipping,
    /// no noise floor): m = (Bᵀ A)(Aᵀ A)⁻¹.
    static func solve(from a: [Float], to b: [Float]) -> [Float] {
        var ata = [Double](repeating: 0, count: 9)
        var bta = [Double](repeating: 0, count: 9)
        var used = 0
        for p in stride(from: 0, to: min(a.count, b.count) - 3, by: 4) {
            let x = [Double(a[p]), Double(a[p + 1]), Double(a[p + 2])]
            let y = [Double(b[p]), Double(b[p + 1]), Double(b[p + 2])]
            guard (x + y).allSatisfy({ $0 > 0.002 && $0 < 0.9 }) else { continue }
            used += 1
            for i in 0..<3 {
                for j in 0..<3 {
                    ata[i * 3 + j] += x[i] * x[j]
                    bta[i * 3 + j] += y[i] * x[j]
                }
            }
        }
        guard used >= 50, let inv = invert3(ata) else { return diagonalFallback(from: a, to: b) }
        return (0..<9).map { k in
            let i = k / 3, j = k % 3
            return Float((0..<3).reduce(0.0) { $0 + bta[i * 3 + $1] * inv[$1 * 3 + j] })
        }
    }

    /// Too few usable pixels (a nearly black or blown frame): per-channel gains of the means.
    private static func diagonalFallback(from a: [Float], to b: [Float]) -> [Float] {
        var sa = [Double](repeating: 1e-9, count: 3), sb = [Double](repeating: 1e-9, count: 3)
        for p in stride(from: 0, to: min(a.count, b.count) - 3, by: 4) {
            for c in 0..<3 { sa[c] += Double(a[p + c]); sb[c] += Double(b[p + c]) }
        }
        let g = (0..<3).map { Float(sb[$0] / sa[$0]) }
        return [g[0], 0, 0, 0, g[1], 0, 0, 0, g[2]]
    }

    private static func invert3(_ m: [Double]) -> [Double]? {
        let c00 = m[4] * m[8] - m[5] * m[7], c01 = m[5] * m[6] - m[3] * m[8], c02 = m[3] * m[7] - m[4] * m[6]
        let det = m[0] * c00 + m[1] * c01 + m[2] * c02
        guard abs(det) > 1e-12 else { return nil }
        let inv = [
            c00, m[2] * m[7] - m[1] * m[8], m[1] * m[5] - m[2] * m[4],
            c01, m[0] * m[8] - m[2] * m[6], m[2] * m[3] - m[0] * m[5],
            c02, m[1] * m[6] - m[0] * m[7], m[0] * m[4] - m[1] * m[3],
        ]
        return inv.map { $0 / det }
    }

    fileprivate static func render(_ image: CIImage, context: CIContext) -> [Float] {
        let extent = image.extent.integral
        let w = Int(extent.width), h = Int(extent.height)
        var out = [Float](repeating: 0, count: w * h * 4)
        out.withUnsafeMutableBytes { buf in
            context.render(image, toBitmap: buf.baseAddress!, rowBytes: w * 16, bounds: extent,
                           format: .RGBAf, colorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB))
        }
        return out
    }
}
