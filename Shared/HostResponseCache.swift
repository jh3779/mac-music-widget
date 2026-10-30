import Foundation

/// Publish completed model responses; network reads never wait for Apple Events
/// or other work on the application's main queue.
final class HostResponseCache {
    struct Snapshot {
        let state: Data
        let artwork: Data?
    }

    private let lock = NSLock()
    private var published = Snapshot(state: Data("{}".utf8), artwork: nil)

    func publish(state: Data, artwork: Data?) {
        let next = Snapshot(state: state, artwork: artwork)
        lock.lock()
        published = next
        lock.unlock()
    }

    func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return published
    }
}
