import XCTest
@testable import ScreenCaster

final class SharedConfigTests: XCTestCase {

    private let defaults = SharedConfig.sharedDefaults

    override func setUp() {
        super.setUp()
        // Clear all keys before each test
        defaults.removeObject(forKey: SharedConfig.rtmpURLKey)
        defaults.removeObject(forKey: "video_bitrate_mbps")
        defaults.removeObject(forKey: "video_fps")
    }

    // MARK: - Stream URL

    func testDefaultStreamURL() {
        XCTAssertEqual(SharedConfig.streamURL, SharedConfig.defaultStreamURL)
    }

    func testSetAndGetStreamURL() {
        SharedConfig.streamURL = "rtmp://10.0.0.1:1935/live/test"
        XCTAssertEqual(SharedConfig.streamURL, "rtmp://10.0.0.1:1935/live/test")
    }

    func testRtmpURLAliasReadsStreamURL() {
        SharedConfig.streamURL = "rtmp://alias-test/live"
        XCTAssertEqual(SharedConfig.rtmpURL, "rtmp://alias-test/live")
    }

    func testRtmpURLAliasWritesStreamURL() {
        SharedConfig.rtmpURL = "rtmp://alias-write/live"
        XCTAssertEqual(SharedConfig.streamURL, "rtmp://alias-write/live")
    }

    // MARK: - Stream protocol detection

    func testStreamProtocolFromRTMPUrl() {
        SharedConfig.streamURL = "rtmp://192.168.1.11:1935/live/iphone"
        XCTAssertEqual(SharedConfig.streamProtocol, .rtmp)
    }

    func testStreamProtocolFromHTTPUrl() {
        SharedConfig.streamURL = "http://192.168.1.11:8889/live/iphone/whip"
        XCTAssertEqual(SharedConfig.streamProtocol, .whip)
    }

    // MARK: - Video bitrate

    func testDefaultVideoBitrate() {
        XCTAssertEqual(SharedConfig.videoBitrateMbps, SharedConfig.defaultVideoBitrateMbps)
    }

    func testSetAndGetVideoBitrate() {
        SharedConfig.videoBitrateMbps = 8
        XCTAssertEqual(SharedConfig.videoBitrateMbps, 8)
    }

    func testVideoBitrateClampedToMax() {
        SharedConfig.videoBitrateMbps = 50
        XCTAssertEqual(SharedConfig.videoBitrateMbps, 15)
    }

    func testVideoBitrateClampedToMin() {
        SharedConfig.videoBitrateMbps = 0
        XCTAssertEqual(SharedConfig.videoBitrateMbps, 1)
    }

    // MARK: - FPS

    func testDefaultFps() {
        XCTAssertEqual(SharedConfig.fps, SharedConfig.defaultFps)
    }

    func testSetAndGetFps() {
        SharedConfig.fps = 60
        XCTAssertEqual(SharedConfig.fps, 60)
    }

    func testInvalidFpsFallsBackToDefault() {
        SharedConfig.fps = 45 // not in fpsOptions
        XCTAssertEqual(SharedConfig.fps, SharedConfig.defaultFps)
    }

    func testAllFpsOptionsAccepted() {
        for fps in SharedConfig.fpsOptions {
            SharedConfig.fps = fps
            XCTAssertEqual(SharedConfig.fps, fps)
        }
    }
}
