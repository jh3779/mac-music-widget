import XCTest
@testable import MediaCore

final class ConnectionTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_000)
    func snapshot(tab: Int = 1, received: Date) -> WebMediaSnapshot {
        WebMediaSnapshot(tabID: tab, videoID: "dQw4w9WgXcQ", title: "Video", author: "Channel",
            isPlaying: true, documentID: "7A6341CD-1052-41CC-A8A5-F3AA4B9E2D88", canGoNext: true,
            canGoPrevious: false, receivedAt: received, changedAt: received, source: "safariYouTube")
    }
    func testCreatorNameIsVisibleForSafariAndMusicAndEmptyNamesAreExplicit() {
        var state = NowPlaying.empty
        state.sourceActive = "safariYouTube"; state.artist = "  Creator\n Name  "
        XCTAssertEqual(state.creatorLabel, "Creator Name")
        XCTAssertEqual(state.creatorRole, "채널")
        state.sourceActive = "youtubeMusic"
        XCTAssertEqual(state.creatorRole, "아티스트")
        state.artist = " "
        XCTAssertEqual(state.creatorLabel, "아티스트 정보 없음")
        state.sourceActive = "safariYouTube"
        XCTAssertEqual(state.creatorLabel, "채널 정보 없음")
    }

    func testNoEvidencePingNoMediaAndExpiredMediaHaveDifferentRecoveryStates() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WebMediaStore(directory: root)
        XCTAssertEqual(store.connectionState(source: "safariYouTube", now: now), .extensionNotConnected)
        try store.recordPing(profile: "default", now: now)
        XCTAssertEqual(store.connectionState(source: "safariYouTube", now: now), .reconnectPage)
        try store.remove(tabID: 1, profile: "default", source: "safariYouTube", now: now)
        XCTAssertEqual(store.connectionState(source: "safariYouTube", now: now), .waitingForMedia)
        try store.save(snapshot(received: now.addingTimeInterval(1)), profile: "default")
        XCTAssertEqual(store.connectionState(source: "safariYouTube", now: now.addingTimeInterval(2)), .ready)
        // Opening the popup must not disguise an expired page as a healthy player.
        try store.recordPing(profile: "default", now: now.addingTimeInterval(50))
        XCTAssertEqual(store.connectionState(source: "safariYouTube", now: now.addingTimeInterval(50)), .updatesDelayed)
        try store.remove(tabID: 1, profile: "default", now: now.addingTimeInterval(51))
        XCTAssertEqual(store.connectionState(source: "safariYouTube", now: now.addingTimeInterval(52)), .waitingForMedia)
    }

    func testUnrelatedTabClosesDoNotCreateHealthRecordsOrHideOtherPlayingTabs() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WebMediaStore(directory: root)
        try store.remove(tabID: 99, profile: "default", now: now)
        XCTAssertEqual(store.connectionState(now: now), .extensionNotConnected)
        try store.save(snapshot(received: now), profile: "default")
        try store.remove(tabID: 2, profile: "default", source: "safariYouTube", now: now.addingTimeInterval(1))
        XCTAssertEqual(store.connectionState(now: now.addingTimeInterval(2)), .ready)
        XCTAssertThrowsError(try store.recordPing(profile: "../../escape", now: now))
        XCTAssertThrowsError(try store.remove(tabID: 3, profile: "default", source: "instagram", now: now))
    }

    func testContactRecordsAreBoundedExpireAndContainNoMediaTitles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WebMediaStore(directory: root)
        for tab in 1...80 {
            try store.remove(tabID: tab, profile: "default", source: "safariYouTube", now: now.addingTimeInterval(Double(tab)))
        }
        let records = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("Health"), includingPropertiesForKeys: nil)
        XCTAssertLessThanOrEqual(records.count, 64)
        XCTAssertEqual(store.connectionState(now: now.addingTimeInterval(1_000)), .extensionNotConnected)
        for record in records {
            let content = try String(contentsOf: record, encoding: .utf8)
            XCTAssertFalse(content.contains("title")); XCTAssertFalse(content.contains("author")); XCTAssertFalse(content.contains("http"))
        }
    }

    func testAppRecoveryLinksAreBoundToTheContainingAppAndFixedActions() {
        let id = "com.example.media"
        let open = HostAppLink.url(.open, extensionIdentifier: id + ".widget")!
        XCTAssertEqual(HostAppLink.action(for: open, hostIdentifier: id), .open)
        let settings = HostAppLink.url(.safariSettings, extensionIdentifier: id + ".safari")!
        XCTAssertEqual(HostAppLink.action(for: settings, hostIdentifier: id), .safariSettings)
        for url in ["https://open", "com.evil.app://open", id + "://open?url=https://evil.test", id + "://open/file", id + "://user@open", id + "://unknown", id + "://open#other"] {
            XCTAssertNil(HostAppLink.action(for: URL(string: url)!, hostIdentifier: id))
        }
        XCTAssertNil(HostAppLink.url(.open, extensionIdentifier: "$(PREFIX).widget"))
    }
}
