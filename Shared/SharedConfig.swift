import Foundation

enum StreamProtocol: Equatable {
    case rtmp
    case whip

    init(url: String) {
        let lower = url.lowercased()
        if lower.hasPrefix("rtmp://") || lower.hasPrefix("rtmps://") {
            self = .rtmp
        } else {
            self = .whip
        }
    }

    var label: String {
        switch self {
        case .rtmp: return "RTMP"
        case .whip: return "WebRTC (WHIP)"
        }
    }
}

enum SharedConfig {
    static let appGroupID = "group.com.dayouxia.ScreenCaster"
    static let rtmpURLKey = "rtmp_url"  // Keep key name for backward compatibility
    static let defaultStreamURL = "rtmp://192.168.1.11:1935/live/iphone"

    static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupID)!
    }

    static var streamURL: String {
        get { sharedDefaults.string(forKey: rtmpURLKey) ?? defaultStreamURL }
        set { sharedDefaults.set(newValue, forKey: rtmpURLKey) }
    }

    /// Backward-compatible alias
    static var rtmpURL: String {
        get { streamURL }
        set { streamURL = newValue }
    }

    static var streamProtocol: StreamProtocol {
        StreamProtocol(url: streamURL)
    }

    private static let videoBitrateKey = "video_bitrate_mbps"
    static let defaultVideoBitrateMbps = 10

    private static let fpsKey = "video_fps"
    static let defaultFps = 30
    static let fpsOptions = [15, 20, 24, 30, 60]

    /// Video frame rate
    static var fps: Int {
        get {
            let val = sharedDefaults.integer(forKey: fpsKey)
            return fpsOptions.contains(val) ? val : defaultFps
        }
        set { sharedDefaults.set(newValue, forKey: fpsKey) }
    }

    /// Video bitrate in Mbps (1–15)
    static var videoBitrateMbps: Int {
        get {
            let val = sharedDefaults.integer(forKey: videoBitrateKey)
            return val > 0 ? min(val, 15) : defaultVideoBitrateMbps
        }
        set { sharedDefaults.set(max(1, min(newValue, 15)), forKey: videoBitrateKey) }
    }
}
