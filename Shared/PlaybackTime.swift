import Foundation

/// A bounded observation, projected only while the player is actually advancing.
struct PlaybackTime {
    static let maximum: Double = 365 * 24 * 60 * 60
    let elapsed: Double
    let duration: Double
    let rate: Double
    let isAdvancing: Bool
    let isLive: Bool

    init(elapsed: Double, duration: Double, rate: Double = 1, isAdvancing: Bool, isLive: Bool = false) {
        self.isLive = isLive
        self.duration = !isLive && duration.isFinite && duration > 0 && duration <= Self.maximum ? duration : 0
        let position = elapsed.isFinite ? min(Self.maximum, max(0, elapsed)) : 0
        self.elapsed = self.duration > 0 ? min(self.duration, position) : position
        self.rate = rate.isFinite && rate >= 0 && rate <= 16 ? rate : 1
        self.isAdvancing = isAdvancing && self.rate > 0
    }

    var hasDuration: Bool { duration > 0 && !isLive }

    func position(since capturedAt: Date, at date: Date) -> Double {
        let offset = isAdvancing ? max(0, date.timeIntervalSince(capturedAt)) * rate : 0
        return min(hasDuration ? duration : Self.maximum, elapsed + offset)
    }

    /// SwiftUI's system-managed timer runs at 1x. Other rates use timeline samples.
    func timerInterval(since capturedAt: Date) -> ClosedRange<Date>? {
        guard hasDuration, isAdvancing, rate == 1 else { return nil }
        let start = capturedAt.addingTimeInterval(-elapsed)
        return start...start.addingTimeInterval(duration)
    }

    static func clock(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "--:--" }
        let value = Int(min(max(0, seconds), maximum))
        if value >= 3_600 { return "\(value / 3_600):" + String(format: "%02d:%02d", value / 60 % 60, value % 60) }
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}
