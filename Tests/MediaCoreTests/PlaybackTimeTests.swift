import XCTest
@testable import MediaCore

final class PlaybackTimeTests: XCTestCase {
    let captured = Date(timeIntervalSince1970: 1_000)

    func testPlayingTimeAdvancesPausedTimeStaysAndEndIsClamped() {
        let playing = PlaybackTime(elapsed: 83, duration: 296, isAdvancing: true)
        XCTAssertEqual(playing.position(since: captured, at: captured.addingTimeInterval(10)), 93)
        XCTAssertEqual(playing.position(since: captured, at: captured.addingTimeInterval(500)), 296)
        let paused = PlaybackTime(elapsed: 83, duration: 296, isAdvancing: false)
        XCTAssertEqual(paused.position(since: captured, at: captured.addingTimeInterval(10)), 83)
        XCTAssertEqual(PlaybackTime.clock(83), "1:23")
        XCTAssertEqual(PlaybackTime.clock(3_661), "1:01:01")
        XCTAssertEqual(PlaybackTime.clock(.infinity), "--:--")
    }

    func testPlaybackSpeedLiveAndInvalidInputsDoNotInventFiniteLengths() {
        let fast = PlaybackTime(elapsed: 20, duration: 300, rate: 2, isAdvancing: true)
        XCTAssertEqual(fast.position(since: captured, at: captured.addingTimeInterval(10)), 40)
        XCTAssertNil(fast.timerInterval(since: captured), "The system timer ticks at 1x only")
        XCTAssertNotNil(PlaybackTime(elapsed: 20, duration: 300, isAdvancing: true).timerInterval(since: captured))
        let live = PlaybackTime(elapsed: 100, duration: .infinity, isAdvancing: true, isLive: true)
        XCTAssertFalse(live.hasDuration)
        XCTAssertNil(live.timerInterval(since: captured))
        let invalid = PlaybackTime(elapsed: .nan, duration: -1, isAdvancing: false)
        XCTAssertEqual(invalid.elapsed, 0)
        XCTAssertEqual(invalid.duration, 0)
    }

    func testNativeTimingIsValidatedAndMissingFieldsRemainCompatible() throws {
        var message: [String: Any] = ["version": 1, "tabID": 1, "videoID": "dQw4w9WgXcQ",
            "documentID": "7A6341CD-1052-41CC-A8A5-F3AA4B9E2D88", "title": "Video", "author": "Channel",
            "isPlaying": true, "canGoNext": true, "canGoPrevious": false]
        XCTAssertEqual(try WebMediaSnapshot.decode(message).playbackTime.elapsed, 0)
        message.merge(["elapsed": 83.5, "duration": 296.0, "playbackRate": 1.0, "isAdvancing": true, "isLive": false]) { _, new in new }
        let value = try WebMediaSnapshot.decode(message, now: captured)
        XCTAssertEqual(value.playbackTime.position(since: value.receivedAt, at: captured.addingTimeInterval(2)), 85.5)
        for (key, bad) in [("elapsed", -1 as Any), ("duration", Double.infinity), ("playbackRate", true), ("isAdvancing", "yes"), ("isLive", 1)] {
            var invalid = message; invalid[key] = bad
            XCTAssertThrowsError(try WebMediaSnapshot.decode(invalid), key)
        }
    }

    func testSeekRequestsARefreshButOrdinaryClockTicksDoNot() {
        var gate = WidgetReloadGate()
        var state = NowPlaying.empty
        state.hasTab = true; state.title = "Video"; state.duration = 300
        state.elapsed = 20; state.isPlaying = true; state.capturedAt = captured
        XCTAssertTrue(gate.shouldReload(state, now: captured))
        state.elapsed = 55; state.capturedAt = captured.addingTimeInterval(35)
        XCTAssertFalse(gate.shouldReload(state, now: state.capturedAt))
        state.elapsed = 150; state.capturedAt = captured.addingTimeInterval(36)
        XCTAssertTrue(gate.shouldReload(state, now: state.capturedAt))
    }

    func testNonUnitSpeedUsesBoundedTimelineSamplesAndEndsWithStaleState() {
        var state = NowPlaying.empty
        state.hasTab = true; state.isPlaying = true; state.duration = 600; state.elapsed = 20
        state.playbackRate = 2; state.isAdvancing = true; state.capturedAt = captured
        state.validUntil = captured.addingTimeInterval(45)
        let entries = WidgetDisplaySnapshot.timeline(for: state, now: captured)
        XCTAssertEqual(entries.count, 11)
        XCTAssertEqual(entries[1].date, captured.addingTimeInterval(30))
        XCTAssertEqual(entries[1].state.playbackTime.position(since: captured, at: entries[1].date), 80)
        XCTAssertTrue(entries.last!.isStale)
        XCTAssertEqual(entries.last!.date, captured.addingTimeInterval(300))
    }
}
