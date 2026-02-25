import XCTest
@testable import ScreenCaster

final class StreamProtocolTests: XCTestCase {

    // MARK: - URL parsing

    func testRTMPUrl() {
        let proto = StreamProtocol(url: "rtmp://192.168.1.11:1935/live/iphone")
        XCTAssertEqual(proto, .rtmp)
    }

    func testRTMPSUrl() {
        let proto = StreamProtocol(url: "rtmps://example.com/live/stream")
        XCTAssertEqual(proto, .rtmp)
    }

    func testRTMPUrlCaseInsensitive() {
        let proto = StreamProtocol(url: "RTMP://192.168.1.11/live")
        XCTAssertEqual(proto, .rtmp)
    }

    func testHTTPUrlDetectedAsWHIP() {
        let proto = StreamProtocol(url: "http://192.168.1.11:8889/live/iphone/whip")
        XCTAssertEqual(proto, .whip)
    }

    func testHTTPSUrlDetectedAsWHIP() {
        let proto = StreamProtocol(url: "https://example.com/whip/endpoint")
        XCTAssertEqual(proto, .whip)
    }

    func testEmptyUrlDefaultsToWHIP() {
        let proto = StreamProtocol(url: "")
        XCTAssertEqual(proto, .whip)
    }

    func testGarbageUrlDefaultsToWHIP() {
        let proto = StreamProtocol(url: "not-a-url")
        XCTAssertEqual(proto, .whip)
    }

    // MARK: - Label

    func testRTMPLabel() {
        XCTAssertEqual(StreamProtocol.rtmp.label, "RTMP")
    }

    func testWHIPLabel() {
        XCTAssertEqual(StreamProtocol.whip.label, "WebRTC (WHIP)")
    }
}
