import Foundation

/// Images served to the web page at app://local/__raw/<name>.jpg (or .png), so they
/// never round-trip through base64.
///
/// - Previews live in memory. A `key` (for example "<item>-film") replaces that key's
///   older preview, so a batch keeps one film and one compare preview per photo.
///   At most `limit` previews are kept; the oldest go first.
/// - Sources (a picked JPEG/PNG, or a HEIC turned into JPEG) are served from their temp
///   file on disk, so a batch of photos is not held in memory.
final class PreviewStore {
    static let shared = PreviewStore()
    static let pathPrefix = "/__raw/"
    static let limit = 128
    private let lock = NSLock()
    private var items: [(name: String, key: String?, data: Data)] = []
    private var files: [String: URL] = [:]
    private var counter = 0

    /// `ext` sets the MIME type the scheme handler serves (jpg or png).
    func put(_ data: Data, ext: String = "jpg", key: String? = nil) -> String {
        lock.lock(); defer { lock.unlock() }
        counter += 1
        let name = "p\(counter).\(ext)"
        let kept = key.map { k in items.filter { $0.key != k } } ?? items
        items = Array((kept + [(name, key, data)]).suffix(Self.limit))
        return "app://local\(Self.pathPrefix)\(name)"
    }

    /// Serves a file we own (in our temp folder) without loading it now.
    func putFile(_ url: URL) -> String {
        lock.lock(); defer { lock.unlock() }
        counter += 1
        let ext = url.pathExtension.lowercased() == "png" ? "png" : "jpg"
        let name = "s\(counter).\(ext)"
        files[name] = url
        return "app://local\(Self.pathPrefix)\(name)"
    }

    func removeAll() {
        lock.lock(); defer { lock.unlock() }
        items = []
        files = [:]
    }

    /// Previews plus sources.
    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return items.count + files.count
    }

    func get(path: String) -> Data? {
        guard path.hasPrefix(Self.pathPrefix) else { return nil }
        let name = String(path.dropFirst(Self.pathPrefix.count))
        lock.lock()
        let data = items.first { $0.name == name }?.data
        let file = files[name]
        lock.unlock()
        return data ?? file.flatMap { try? Data(contentsOf: $0) }
    }
}
