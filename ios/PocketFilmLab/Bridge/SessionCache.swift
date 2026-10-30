import Foundation

/// Open RAW sessions for a batch, keyed by item id. Each session holds a reduced
/// scene-linear decode (~25 MB at a 2048 px edge), so only a few are kept: the photo on
/// screen (the "hero") plus the most recent others. Use only on the render queue.
final class SessionCache {
    let capacity: Int
    private let engine: FilmEngine
    private var order: [(id: String, session: RawSession)] = []
    private var heroID: String?

    init(engine: FilmEngine, capacity: Int = 2) {
        self.engine = engine
        self.capacity = max(1, capacity)
    }

    var count: Int { order.count }
    var ids: [String] { order.map(\.id) }

    /// The session for `id`, opening it from `url` if needed. `hero` keeps it cached
    /// while other photos are developed in the background.
    func session(id: String, url: URL, hero: Bool) throws -> RawSession {
        if hero { heroID = id }
        if let i = order.firstIndex(where: { $0.id == id }) {
            let hit = order.remove(at: i)
            order.append(hit)
            return hit.session
        }
        let session = try RawSession(url: url, engine: engine)
        order.append((id, session))
        evict()
        return session
    }

    /// A cached session, or nil. Does not open anything.
    func existing(id: String) -> RawSession? {
        order.first { $0.id == id }?.session
    }

    func removeAll() {
        order = []
        heroID = nil
    }

    private func evict() {
        while order.count > capacity {
            // Oldest first, but never the hero unless it is the only one left to drop.
            let victim = order.firstIndex { $0.id != heroID } ?? 0
            order.remove(at: victim)
        }
    }
}
