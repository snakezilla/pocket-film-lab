import Foundation

/// In-memory previews served to the web page at app://local/__raw/<name>.jpg,
/// so preview images never round-trip through base64. Keeps only the newest few.
final class PreviewStore {
    static let shared = PreviewStore()
    static let pathPrefix = "/__raw/"
    private let lock = NSLock()
    private var items: [(name: String, data: Data)] = []
    private var counter = 0

    func put(_ data: Data) -> String {
        lock.lock(); defer { lock.unlock() }
        counter += 1
        let name = "p\(counter).jpg"
        items = Array((items + [(name, data)]).suffix(6))
        return "app://local\(Self.pathPrefix)\(name)"
    }

    func get(path: String) -> Data? {
        guard path.hasPrefix(Self.pathPrefix) else { return nil }
        let name = String(path.dropFirst(Self.pathPrefix.count))
        lock.lock(); defer { lock.unlock() }
        return items.first { $0.name == name }?.data
    }
}
