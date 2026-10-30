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
        guard force || changed else { return false }
        guard force || now.timeIntervalSince(lastReload) >= minimumInterval else { return false }
        lastState = current
        lastReload = now
        return true
    }
}
