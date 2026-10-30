import XCTest
@testable import MediaCore

final class WebMediaTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func snapshot(_ id: Int = 1, playing: Bool = true, received: Date? = nil, changed: Date? = nil) -> WebMediaSnapshot {
        WebMediaSnapshot(tabID: id, videoID: "dQw4w9WgXcQ", title: "A video", author: "A channel",
                         isPlaying: playing, documentID: "7A6341CD-1052-41CC-A8A5-F3AA4B9E2D88", canGoNext: true, canGoPrevious: false, receivedAt: received ?? now, changedAt: changed ?? now)
    }
    func testOnlyFreshSnapshotsParticipate() {
        XCTAssertNil(WebMediaSnapshot.select([snapshot(received: now.addingTimeInterval(-46))], now: now))
        XCTAssertNil(WebMediaSnapshot.select([snapshot(received: now.addingTimeInterval(60))], now: now))
    }
    func testPlayingWinsAndHeartbeatDoesNotStealSelection() {
        let paused = snapshot(1, playing: false, changed: now.addingTimeInterval(1))
        let playing = snapshot(2, changed: now.addingTimeInterval(-10))
        XCTAssertEqual(WebMediaSnapshot.select([paused, playing], now: now)?.tabID, 2)
        let heartbeat = snapshot(3, changed: now.addingTimeInterval(-20))
        XCTAssertEqual(WebMediaSnapshot.select([heartbeat, playing], now: now)?.tabID, 2)
    }
    func testNativeBoundaryRejectsUntrustedMetadata() throws {
        let valid: [String: Any] = ["version": 1, "tabID": 4, "videoID": "dQw4w9WgXcQ", "title": " Video ", "author": "Channel", "isPlaying": true, "documentID": "7A6341CD-1052-41CC-A8A5-F3AA4B9E2D88", "canGoNext": true, "canGoPrevious": false]
        let decoded = try WebMediaSnapshot.decode(valid, now: now)
        XCTAssertEqual(decoded.title, "Video")
        XCTAssertEqual(decoded.artworkURL, "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg")
        for (key, value) in [("version", 2 as Any), ("tabID", -1), ("videoID", "../private"), ("title", ""), ("title", String(repeating: "x", count: 513)), ("isPlaying", "true")] {
            var bad = valid; bad[key] = value
            XCTAssertThrowsError(try WebMediaSnapshot.decode(bad, now: now), key)
        }
    }
    func testStoreUpdatesClearsAndExpiresWithoutHeartbeatReordering() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WebMediaStore(directory: root)
        try store.save(snapshot(), profile: "default")
        try store.save(snapshot(received: now.addingTimeInterval(10), changed: now.addingTimeInterval(10)), profile: "default")
        XCTAssertEqual(store.snapshots(now: now.addingTimeInterval(10)).first?.changedAt, now)
        XCTAssertEqual(store.snapshots(now: now.addingTimeInterval(56)).count, 0)
        try store.save(snapshot(), profile: "default")
        try store.remove(tabID: 1, profile: "default")
        XCTAssertTrue(store.snapshots(now: now).isEmpty)
        XCTAssertThrowsError(try store.save(snapshot(), profile: "../../escape"))
    }
    func testProfilesDoNotOverwriteAndCorruptFilesAreIgnored() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WebMediaStore(directory: root)
        try store.save(snapshot(), profile: "default")
        try store.save(snapshot(), profile: UUID().uuidString)
        try Data("broken".utf8).write(to: root.appendingPathComponent("bad.json"))
        XCTAssertEqual(store.snapshots(now: now).count, 2)
    }
    func testReloadGateCoalescesChangesButEventuallyPublishesLatest() {
        var gate = WidgetReloadGate()
        var state = NowPlaying.empty
        state.title = "First"; state.hasTab = true
        XCTAssertTrue(gate.shouldReload(state, now: now))
        state.capturedAt = now.addingTimeInterval(20); state.elapsed = 20
        XCTAssertFalse(gate.shouldReload(state, now: now.addingTimeInterval(20)))
        state.artworkURL = "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg"
        XCTAssertFalse(gate.shouldReload(state, now: now.addingTimeInterval(21)))
        XCTAssertTrue(gate.shouldReload(state, now: now.addingTimeInterval(31)))
        state.isPlaying = true
        XCTAssertTrue(gate.shouldReload(state, now: now.addingTimeInterval(32), force: true))
    }
    func testCommandsAreBoundToDocumentExpireAndAreConsumedOnce() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WebMediaStore(directory: root)
        let media = snapshot()
        try store.enqueue(.playPause, for: media, now: now)
        XCTAssertNil(store.takeCommand(for: snapshot(2), now: now))
        XCTAssertEqual(store.takeCommand(for: media, now: now)?.action, .playPause)
        XCTAssertNil(store.takeCommand(for: media, now: now))
        try store.enqueue(.next, for: media, now: now)
        XCTAssertNil(store.takeCommand(for: media, now: now.addingTimeInterval(9)))
    }

    func testVideoSourceIsNamedCorrectly() {
        var state = NowPlaying.empty
        state.sourceActive = "safariYouTube"
        XCTAssertEqual(state.sourceLabel, "Auto — Safari YouTube")
        XCTAssertTrue(state.supportsTransport)
        state.sourceActive = "spotify"
        XCTAssertTrue(state.supportsTransport)
    }
}
