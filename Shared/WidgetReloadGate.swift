import Foundation

/// Coalesce visible changes; progress/heartbeats alone never consume reload budget.
struct WidgetReloadGate {
    private var lastState: NowPlaying?
    private var lastReload = Date.distantPast
    var minimumInterval: TimeInterval = 30

    mutating func shouldReload(_ next: NowPlaying, now: Date = Date(), force: Bool = false) -> Bool {
        var current = next
        current.capturedAt = .distantPast
        current.elapsed = 0
        current.validUntil = nil
        let changed = lastState != current
        // Safari's precomputed expiry entry must be renewed while it is still playing.
        // This is only a request: WidgetKit may throttle it even after this interval.
        let renewLease = next.validUntil != nil && now.timeIntervalSince(lastReload) >= minimumInterval
        guard force || changed || renewLease else { return false }
        guard force || now.timeIntervalSince(lastReload) >= minimumInterval else { return false }
        lastState = current
        lastReload = now
        return true
    }
}
