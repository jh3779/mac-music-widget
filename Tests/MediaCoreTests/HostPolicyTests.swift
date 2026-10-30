import XCTest
@testable import MediaCore

final class HostPolicyTests: XCTestCase {
    func testHTTPResponseUsesLastCompletedPublicationWhileModelWorkWaits() {
        let cache = HostResponseCache()
        let published = Data("{\"title\":\"Song\"}".utf8)
        cache.publish(state: published, artwork: Data([1, 2, 3]))
        let modelBlocked = expectation(description: "model work started")
        let responseRead = expectation(description: "HTTP response does not await model")
        let releaseModel = DispatchSemaphore(value: 0)
        DispatchQueue(label: "test.delayed-player").async {
            modelBlocked.fulfill()
            releaseModel.wait()
        }
        defer { releaseModel.signal() }
        wait(for: [modelBlocked], timeout: 1)
        DispatchQueue.global().async {
            let response = cache.snapshot()
            XCTAssertEqual(response.state, published)
            XCTAssertEqual(response.artwork, Data([1, 2, 3]))
            responseRead.fulfill()
        }
        wait(for: [responseRead], timeout: 0.5)
    }

    func testResponsePublicationNeverMixesDifferentVersions() {
        let cache = HostResponseCache()
        cache.publish(state: Data([0]), artwork: Data([0]))
        DispatchQueue.concurrentPerform(iterations: 200) { iteration in
            let value = Data([UInt8(iteration)])
            cache.publish(state: value, artwork: value)
            let response = cache.snapshot()
            XCTAssertEqual(response.state, response.artwork)
        }
    }

    func testSlowBrowserRequestSurvivesPollTicksWithoutQueuingDuplicates() {
        var cache = BrowserPollCache<String>()
        let now = Date(timeIntervalSince1970: 1_000)
        let request = cache.beginRequest()!
        for tick in 1...5 {
            XCTAssertNil(cache.beginRequest())
            XCTAssertNil(cache.latest(now: now.addingTimeInterval(Double(tick))))
        }
        XCTAssertTrue(cache.complete(request, value: "Browser song", now: now.addingTimeInterval(6)))
        XCTAssertEqual(cache.latest(now: now.addingTimeInterval(7)), "Browser song")
        XCTAssertNotNil(cache.beginRequest())
    }

    func testBrowserConfigurationChangeRejectsOldResultAndClearsCachedPlayback() {
        var cache = BrowserPollCache<String>()
        let now = Date(timeIntervalSince1970: 1_000)
        let first = cache.beginRequest()!
        XCTAssertTrue(cache.complete(first, value: "Old browser", now: now))
        let outstanding = cache.beginRequest()!
        cache.invalidate()
        XCTAssertNil(cache.latest(now: now))
        XCTAssertNil(cache.beginRequest(), "An existing physical request must finish before another is queued")
        XCTAssertFalse(cache.complete(outstanding, value: "Old browser", now: now.addingTimeInterval(1)))
        let replacement = cache.beginRequest()!
        XCTAssertTrue(cache.complete(replacement, value: "New browser", now: now.addingTimeInterval(2)))
        XCTAssertEqual(cache.latest(now: now.addingTimeInterval(3)), "New browser")
        XCTAssertNil(cache.latest(now: now.addingTimeInterval(48)), "A hung browser must not retain playing metadata indefinitely")
    }

    func testMusicOnlyBuildSkipsUnsupportedSafariAndNormalizesSavedSelection() {
        enum Source: CaseIterable { case auto, safari, youtubeMusic, spotify, appleMusic }
        let choices = MediaSourceList(all: Source.allCases, fallback: .auto, safari: .safari, supportsSafari: false)
        XCTAssertEqual(choices.available, [.auto, .youtubeMusic, .spotify, .appleMusic])
        XCTAssertEqual(choices.normalized(.safari), .auto)
        XCTAssertEqual(choices.next(after: .auto), .youtubeMusic)
        XCTAssertEqual(choices.next(after: .appleMusic), .auto)
        XCTAssertEqual(choices.normalized(.spotify), .spotify)
        let full = MediaSourceList(all: Source.allCases, fallback: .auto, safari: .safari, supportsSafari: true)
        XCTAssertEqual(full.next(after: .auto), .safari)
        XCTAssertEqual(full.normalized(.safari), .safari)
    }
}
