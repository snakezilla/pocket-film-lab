import Foundation

/// In-memory previews served to the web page at app://local/__raw/<name>.jpg (or .png),
/// so preview images never round-trip through base64. Keeps only the newest few.
final class PreviewStore {
    static let shared = PreviewStore()
    static let pathPrefix = "/__raw/"
    private let lock = NSLock()
    private var items: [(name: String, data: Data)] = []
    private var counter = 0

    /// `ext` sets the MIME type the scheme handler serves (jpg or png).
    func put(_ data: Data, ext: String = "jpg") -> String {
        lock.lock(); defer { lock.unlock() }
        counter += 1
        let name = "p\(counter).\(ext)"
        items = Array((items + [(name, data)]).suffix(6))
        return "app://local\(Self.pathPrefix)\(name)"
    }

    func removeAll() {
        lock.lock(); defer { lock.unlock() }
        items = []
    }

    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return items.count
    }

    func get(path: String) -> Data? {
        guard path.hasPrefix(Self.pathPrefix) else { return nil }
        let name = String(path.dropFirst(Self.pathPrefix.count))
        lock.lock(); defer { lock.unlock() }
        return items.first { $0.name == name }?.data
    }
}
