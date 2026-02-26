import CoreMedia

/// Timestamp-based frame rate throttle.
///
/// Decides whether a frame should be accepted based on the elapsed time
/// since the last accepted frame. Used to drop excess frames when ReplayKit
/// delivers at the device's native refresh rate (e.g. 60 fps) but a lower
/// target frame rate is configured.
struct FrameThrottle {
    /// Presentation timestamp of the last accepted frame.
    private(set) var lastTimestamp: CMTime = .invalid

    /// Returns `true` if the frame at `pts` should be accepted for the given `fps`.
    ///
    /// Uses a 0.8× tolerance on the minimum interval to accommodate natural
    /// timing jitter from ReplayKit without under-shooting the target rate.
    mutating func shouldAccept(pts: CMTime, fps: Int) -> Bool {
        guard lastTimestamp.isValid else {
            lastTimestamp = pts
            return true
        }
        let elapsed = CMTimeGetSeconds(pts) - CMTimeGetSeconds(lastTimestamp)
        let minInterval = 1.0 / Double(fps)
        if elapsed < minInterval * 0.8 {
            return false
        }
        lastTimestamp = pts
        return true
    }
}
