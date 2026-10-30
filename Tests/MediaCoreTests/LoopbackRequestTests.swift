import XCTest
@testable import MediaCore

final class LoopbackRequestTests: XCTestCase {
    func testCommandRequiresPostAndRejectsWebOrigins() {
        let host = "Host: 127.0.0.1:47893\r\n"
        XCTAssertNotNil(LoopbackRequest("POST /cmd/playPause HTTP/1.1\r\n" + host + "\r\n"))
        XCTAssertNil(LoopbackRequest("GET /cmd/playPause HTTP/1.1\r\n" + host + "\r\n"))
        XCTAssertNil(LoopbackRequest("POST /cmd/playPause HTTP/1.1\r\n" + host + "Origin: https://evil.test\r\n\r\n"))
        XCTAssertNil(LoopbackRequest("POST /cmd/playPause HTTP/1.1\r\nHost: evil.test\r\n\r\n"))
        XCTAssertNil(LoopbackRequest("POST /cmd/unknown HTTP/1.1\r\n" + host + "\r\n"))
    }
    func testDocumentTargetIsValidatedAndPreserved() {
        let id = "7A6341CD-1052-41CC-A8A5-F3AA4B9E2D88"
        let request = LoopbackRequest("POST /cmd/next?document=\(id) HTTP/1.1\r\nHost: 127.0.0.1:47893\r\n\r\n")
        XCTAssertEqual(request?.documentID, id)
        XCTAssertEqual(request?.command, .next)
        XCTAssertNil(LoopbackRequest("POST /cmd/next?document=../../bad HTTP/1.1\r\nHost: 127.0.0.1:47893\r\n\r\n"))
    }
}
