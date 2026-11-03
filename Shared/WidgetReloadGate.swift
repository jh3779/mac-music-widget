import Foundation

/// Coalesce visible changes; progress/heartbeats alone never consume reload budget.
struct WidgetReloadGate {
    private var lastState: NowPlaying?
    private var lastTiming: NowPlaying?
    private var lastReload = Date.distantPast
    var minimumInterval: TimeInterval = 30

    mutating func shouldReload(_ next: NowPlaying, now: Date = Date(), force: Bool = false) -> Bool {
        var current = next
        current.capturedAt = .distantPast
        current.elapsed = 0
        current.validUntil = nil
        let positionChanged = lastTiming.map {
            abs(next.elapsed - $0.playbackTime.position(since: $0.capturedAt, at: next.capturedAt)) > 2
        } ?? false
        let changed = lastState != current || positionChanged
        guard force || changed else { return false }
        guard force || now.timeIntervalSince(lastReload) >= minimumInterval else { return false }
        lastState = current
        lastTiming = next
        lastReload = now
        return true
    }
}
