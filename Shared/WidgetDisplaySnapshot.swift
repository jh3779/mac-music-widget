import Foundation

/// Browser evidence expires quickly for routing commands. WidgetKit's display has a
/// separate lifetime because the system can defer timeline reloads for minutes.
struct WidgetDisplaySnapshot {
    let date: Date
    let state: NowPlaying
    let isStale: Bool

    static func timeline(for state: NowPlaying, now: Date) -> [Self] {
        guard state.hasTab, state.validUntil != nil else {
            return [Self(date: now, state: state, isStale: false)]
        }
        let staleAt = state.capturedAt.addingTimeInterval(300)
        guard staleAt > now else {
            return [Self(date: now, state: state, isStale: true)]
        }
        return [Self(date: now, state: state, isStale: false),
                Self(date: staleAt, state: state, isStale: true)]
    }
}
