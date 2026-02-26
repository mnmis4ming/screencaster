import CoreMedia
import XCTest
@testable import ScreenCaster

final class FrameThrottleTests: XCTestCase {

    // MARK: - Helpers

    private func pts(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 600)
    }

    // MARK: - First frame always accepted

    func testFirstFrameIsAlwaysAccepted() {
        var throttle = FrameThrottle()
        XCTAssertTrue(throttle.shouldAccept(pts: pts(0), fps: 30))
    }

    // MARK: - Dropping frames at 30 fps target

    func testDropsFrameArrivingTooSoonAt30fps() {
        var throttle = FrameThrottle()
        // First frame at t=0
        XCTAssertTrue(throttle.shouldAccept(pts: pts(0), fps: 30))
        // Next frame at t=16ms (typical 60fps interval) — should be dropped
        // minInterval = 1/30 = 33.3ms, threshold = 33.3ms * 0.8 = 26.7ms
        XCTAssertFalse(throttle.shouldAccept(pts: pts(0.016), fps: 30))
    }

    func testAcceptsFrameAfterSufficientIntervalAt30fps() {
        var throttle = FrameThrottle()
        XCTAssertTrue(throttle.shouldAccept(pts: pts(0), fps: 30))
        // Next frame at t=33ms — just at the 33.3ms interval, above 26.7ms threshold
        XCTAssertTrue(throttle.shouldAccept(pts: pts(0.033), fps: 30))
    }

    // MARK: - 60fps passthrough

    func testAllFramesPassAt60fps() {
        var throttle = FrameThrottle()
        // At 60fps target, minInterval = 16.7ms, threshold = 13.3ms
        // Frames arriving at 16ms intervals should all pass
        for i in 0..<10 {
            let accepted = throttle.shouldAccept(pts: pts(Double(i) * 0.016), fps: 60)
            XCTAssertTrue(accepted, "Frame \(i) at \(Double(i) * 0.016)s should be accepted at 60fps")
        }
    }

    // MARK: - 15fps target

    func testDropsThreeOutOfFourFramesAt15fps() {
        var throttle = FrameThrottle()
        // minInterval = 1/15 = 66.7ms, threshold = 53.3ms
        // 60fps source delivers every ~16.7ms
        var accepted = 0
        let total = 60
        for i in 0..<total {
            let t = Double(i) * (1.0 / 60.0)
            if throttle.shouldAccept(pts: pts(t), fps: 15) {
                accepted += 1
            }
        }
        // Should accept roughly 15 out of 60 frames (±2 for boundary effects)
        XCTAssertGreaterThanOrEqual(accepted, 13)
        XCTAssertLessThanOrEqual(accepted, 17)
    }

    // MARK: - Jitter tolerance

    func testAcceptsFrameWithSlightJitterAt30fps() {
        var throttle = FrameThrottle()
        XCTAssertTrue(throttle.shouldAccept(pts: pts(0), fps: 30))
        // Frame arrives 1ms early (32ms instead of 33.3ms) — should still be accepted
        // because 32ms > 26.7ms threshold
        XCTAssertTrue(throttle.shouldAccept(pts: pts(0.032), fps: 30))
    }

    // MARK: - Timestamp tracking

    func testLastTimestampUpdatesOnlyOnAccepted() {
        var throttle = FrameThrottle()
        XCTAssertTrue(throttle.shouldAccept(pts: pts(0), fps: 30))
        XCTAssertEqual(CMTimeGetSeconds(throttle.lastTimestamp), 0, accuracy: 0.001)

        // Dropped frame should NOT update lastTimestamp
        XCTAssertFalse(throttle.shouldAccept(pts: pts(0.010), fps: 30))
        XCTAssertEqual(CMTimeGetSeconds(throttle.lastTimestamp), 0, accuracy: 0.001)

        // Accepted frame updates lastTimestamp
        XCTAssertTrue(throttle.shouldAccept(pts: pts(0.034), fps: 30))
        XCTAssertEqual(CMTimeGetSeconds(throttle.lastTimestamp), 0.034, accuracy: 0.001)
    }

    // MARK: - Invalid initial state

    func testInitialLastTimestampIsInvalid() {
        let throttle = FrameThrottle()
        XCTAssertFalse(throttle.lastTimestamp.isValid)
    }
}
