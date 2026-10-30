import XCTest
@testable import MediaCore

final class WidgetDisplayTests: XCTestCase {
    func testBrowserLeaseExpiryDoesNotEraseArtworkAndTitle() {
        let now = Date(timeIntervalSince1970: 1_000)
        var state = NowPlaying.empty
        state.hasTab = true
        state.title = "Current song"
        state.artworkURL = "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg"
        state.capturedAt = now
        state.validUntil = now.addingTimeInterval(45)
        let entries = WidgetDisplaySnapshot.timeline(for: state, now: now)
        XCTAssertEqual(entries.count, 2)
        XCTAssertFalse(entries[0].isStale)
        XCTAssertEqual(entries[1].date, now.addingTimeInterval(300))
        XCTAssertTrue(entries[1].isStale)
        XCTAssertEqual(entries[1].state.title, state.title)
        XCTAssertEqual(entries[1].state.artworkURL, state.artworkURL)
        XCTAssertTrue(entries[1].state.hasTab)
        // Delayed delivery still keeps the last observation, with a stale label.
        let delayed = WidgetDisplaySnapshot.timeline(for: state, now: now.addingTimeInterval(400))
        XCTAssertEqual(delayed.count, 1)
        XCTAssertTrue(delayed[0].isStale)
        XCTAssertEqual(delayed[0].state.title, state.title)
    }

    func testHeartbeatDoesNotDemandWidgetReloadsToRenewBrowserLease() {
        let now = Date(timeIntervalSince1970: 1_000)
        var state = NowPlaying.empty
        state.hasTab = true
        state.title = "Song"
        state.validUntil = now.addingTimeInterval(45)
        var gate = WidgetReloadGate()
        XCTAssertTrue(gate.shouldReload(state, now: now))
        state.validUntil = now.addingTimeInterval(80)
        state.capturedAt = now.addingTimeInterval(35)
        XCTAssertFalse(gate.shouldReload(state, now: now.addingTimeInterval(35)))
        state.title = "Next song"
        XCTAssertTrue(gate.shouldReload(state, now: now.addingTimeInterval(36)))
    }
}
