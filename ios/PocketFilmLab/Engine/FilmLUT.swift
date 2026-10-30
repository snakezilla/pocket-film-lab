import CoreImage
import Foundation

enum FilmLUTError: Error, LocalizedError {
    case missing(String)
    case badSize(String, expected: Int, actual: Int)

    var errorDescription: String? {
        switch self {
        case .missing(let id): return "Film LUT \(id) is not in the app bundle"
        case .badSize(let id, let expected, let actual): return "Film LUT \(id) has \(actual) bytes, expected \(expected)"
        }
    }
}

/// Log2 shaper parameters. Generated with the cube by tools/make_raw_lut.py.
struct FilmShaper: Decodable, Equatable {
    let midGrey: Float
    let logMin: Float
    let logMax: Float

    /// CPU version of the shaper in FilmLook.ci.metal, for tests and tooling.
    func encode(_ x: Float) -> Float {
        let v = (log2(max(x, 1e-10) / midGrey) - logMin) / (logMax - logMin)
        return min(max(v, 0), 1)
    }
}

/// A scene-linear-in, display-linear-out film cube (negative + print).
struct FilmLUT {
    struct Meta: Decodable {
        let id: String
        let label: String
        let size: Int
        let negative: String
        let print: String
        let shaper: FilmShaper
    }

    let meta: Meta
    /// Float32 RGBA, red fastest. The layout CIColorCube takes.
    let cubeData: Data

    static func load(id: String, bundle: Bundle = .main) throws -> FilmLUT {
        guard let jsonURL = bundle.url(forResource: id, withExtension: "json"),
              let binURL = bundle.url(forResource: id, withExtension: "cube.bin") else {
            throw FilmLUTError.missing(id)
        }
        let meta = try JSONDecoder().decode(Meta.self, from: Data(contentsOf: jsonURL))
        let data = try Data(contentsOf: binURL)
        let expected = meta.size * meta.size * meta.size * 4 * MemoryLayout<Float>.size
        guard data.count == expected else {
            throw FilmLUTError.badSize(id, expected: expected, actual: data.count)
        }
        return FilmLUT(meta: meta, cubeData: data)
    }
}
