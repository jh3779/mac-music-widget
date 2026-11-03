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
        var entries = [Self(date: now, state: state, isStale: false)]
        let timing = state.playbackTime
        if timing.hasDuration, timing.isAdvancing, timing.rate != 1 {
            // The system clock is 1x only; bounded 30-second samples keep other
            // speeds honest without requesting a host reload on every tick.
            for offset in stride(from: 30.0, to: 300.0, by: 30.0) {
                let date = now.addingTimeInterval(offset)
                if date < staleAt { entries.append(Self(date: date, state: state, isStale: false)) }
            }
        }
        entries.append(Self(date: staleAt, state: state, isStale: true))
        return entries
    }
}
