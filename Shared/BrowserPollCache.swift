import Foundation

/// Main-queue state for the legacy asynchronous browser reader. Poll ticks may
/// read the last completed value without queuing more browser work. Only a
/// source/browser configuration change invalidates an outstanding result.
struct BrowserPollCache<Value> {
    struct Request: Equatable {
        fileprivate let epoch: Int
        fileprivate let sequence: Int
    }

    private var epoch = 0
    private var sequence = 0
    private var active: Request?
    private var value: Value?
    private(set) var receivedAt: Date?
    var lifetime: TimeInterval = 45

    mutating func beginRequest() -> Request? {
        guard active == nil else { return nil }
        sequence += 1
        let request = Request(epoch: epoch, sequence: sequence)
        active = request
        return request
    }

    mutating func complete(_ request: Request, value: Value, now: Date = Date()) -> Bool {
        guard request == active else { return false }
        active = nil
        guard request.epoch == epoch else { return false }
        self.value = value
        receivedAt = now
        return true
    }

    mutating func invalidate() {
        epoch += 1
        value = nil
        receivedAt = nil
        // Keep the physical in-flight slot until its callback arrives. Otherwise
        // repeated configuration changes could queue an unbounded Apple Event backlog.
    }

    func latest(now: Date = Date()) -> Value? {
        guard let receivedAt, receivedAt <= now,
              now.timeIntervalSince(receivedAt) < lifetime else { return nil }
        return value
    }
}
