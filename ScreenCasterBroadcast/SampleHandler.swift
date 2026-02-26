import CoreImage
import HaishinKit
import os
import ReplayKit
import RTCHaishinKit
import RTMPHaishinKit
import VideoToolbox

private let log = Logger(subsystem: "com.dayouxia.ScreenCaster.Broadcast", category: "SampleHandler")

final class SampleHandler: RPBroadcastSampleHandler, @unchecked Sendable {
    private var session: (any Session)?
    private var mixer = MediaMixer(captureSessionMode: .manual)

    // Rotation handling
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private var rotatedBufferPool: CVPixelBufferPool?
    private var rotatedPoolSize: CGSize = .zero
    private var encoderConfigured = false
    private var landscapeSize: CGSize = .zero
    private var proto: StreamProtocol = .rtmp

    // Frame rate throttle
    private var frameThrottle = FrameThrottle()

    // Diagnostics
    private var lastLoggedSize: CGSize = .zero
    private var frameCount: Int = 0

    override init() {
        super.init()
        Task {
            await SessionBuilderFactory.shared.register(RTMPSessionFactory())
            await SessionBuilderFactory.shared.register(HTTPSessionFactory())
        }
    }

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        let url = SharedConfig.streamURL
        proto = SharedConfig.streamProtocol
        log.info("🚀 Broadcast starting — url=\(url), proto=\(self.proto.label), bitrate=\(SharedConfig.videoBitrateMbps)Mbps, fps=\(SharedConfig.fps)")
        Task {
            do {
                guard let streamURL = URL(string: url) else {
                    finishBroadcastWithError(
                        NSError(domain: "ScreenCaster", code: -1, userInfo: [
                            NSLocalizedDescriptionKey: "Invalid stream URL: \(url)"
                        ])
                    )
                    return
                }

                session = try await SessionBuilderFactory.shared.make(streamURL).build()

                // Memory optimization: limit video queue and use passthrough mode
                var videoMixerSettings = await mixer.videoMixerSettings
                videoMixerSettings.mode = .passthrough
                await mixer.setVideoMixerSettings(videoMixerSettings)
                await session?.stream.setVideoInputBufferCounts(5)

                // Audio settings: RTMP → AAC 192 kbps, WebRTC → Opus 128 kbps
                var audioSettings = await session!.stream.audioSettings
                switch proto {
                case .rtmp:
                    audioSettings.bitRate = 192 * 1000
                case .whip:
                    audioSettings.bitRate = 128 * 1000
                }
                try await session?.stream.setAudioSettings(audioSettings)

                // Configure audio mixer: single track for app audio
                var audioMixerSettings = await mixer.audioMixerSettings
                audioMixerSettings.tracks[0] = .default
                audioMixerSettings.tracks[0]?.volume = 1.0
                await mixer.setAudioMixerSettings(audioMixerSettings)

                await mixer.startRunning()

                if let session {
                    await mixer.addOutput(session.stream)
                    try await session.connect {}
                }
            } catch {
                finishBroadcastWithError(
                    NSError(domain: "ScreenCaster", code: -2, userInfo: [
                        NSLocalizedDescriptionKey: "Failed to connect: \(error.localizedDescription)"
                    ])
                )
            }
        }

    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        switch sampleBufferType {
        case .video:
            // Frame rate throttle: drop frames that arrive too soon
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            if !frameThrottle.shouldAccept(pts: pts, fps: SharedConfig.fps) {
                return
            }

            let orientation = Self.orientation(from: sampleBuffer)

            // Diagnostic: log pixel buffer dimensions periodically and on change
            if let pb = sampleBuffer.imageBuffer {
                let w = CVPixelBufferGetWidth(pb)
                let h = CVPixelBufferGetHeight(pb)
                let sz = CGSize(width: CGFloat(w), height: CGFloat(h))
                frameCount += 1
                if sz != lastLoggedSize || frameCount % 60 == 0 {
                    let changed = sz != lastLoggedSize ? " [CHANGED]" : ""
                    lastLoggedSize = sz
                    log.info("📐 #\(self.frameCount): \(w)×\(h) orientation=\(orientation.rawValue)\(changed)")
                }
            }

            // Configure encoder once — always use landscape dimensions
            if !encoderConfigured, let dimensions = sampleBuffer.formatDescription?.dimensions {
                let w = CGFloat(dimensions.width)
                let h = CGFloat(dimensions.height)
                landscapeSize = CGSize(width: max(w, h), height: min(w, h))
                encoderConfigured = true
                Task {
                    var videoSettings = await session?.stream.videoSettings
                    videoSettings?.videoSize = landscapeSize
                    videoSettings?.profileLevel = kVTProfileLevel_H264_High_4_2 as String
                    videoSettings?.bitRate = SharedConfig.videoBitrateMbps * 1_000_000
                    videoSettings?.bitRateMode = .average
                    videoSettings?.maxKeyFrameIntervalDuration = 1
                    videoSettings?.allowFrameReordering = false
                    videoSettings?.isHardwareAcceleratedEnabled = true
                    videoSettings?.expectedFrameRate = Float64(SharedConfig.fps)
                    if let videoSettings {
                        try? await session?.stream.setVideoSettings(videoSettings)
                    }
                }
            }

            if let processed = processedVideoBuffer(sampleBuffer, orientation: orientation) {
                Task { await mixer.append(processed) }
            } else {
                Task { await mixer.append(sampleBuffer) }
            }

        case .audioMic:
            break
        case .audioApp:
            if sampleBuffer.dataReadiness == .ready {
                Task { await mixer.append(sampleBuffer, track: 0) }
            }
        @unknown default:
            break
        }
    }

    override func broadcastFinished() {
        Task {
            await mixer.stopRunning()
        }
    }

    // MARK: - Rotation

    /// Reads the RPVideoSampleOrientationKey attachment to determine orientation.
    private static func orientation(from sampleBuffer: CMSampleBuffer) -> CGImagePropertyOrientation {
        guard let value = CMGetAttachment(
            sampleBuffer,
            key: RPVideoSampleOrientationKey as CFString,
            attachmentModeOut: nil
        ) as? NSNumber else {
            return .up
        }
        return CGImagePropertyOrientation(rawValue: value.uint32Value) ?? .up
    }

    /// Processes a video frame for the landscape output canvas.
    /// Step 1: Rotate content upright via VideoFrameProcessor.
    /// Step 2: Aspect-fit and center if dimensions don't match the canvas.
    private func processedVideoBuffer(
        _ sampleBuffer: CMSampleBuffer,
        orientation: CGImagePropertyOrientation
    ) -> CMSampleBuffer? {
        guard let pixelBuffer = sampleBuffer.imageBuffer, landscapeSize != .zero else { return nil }

        let src = CIImage(cvPixelBuffer: pixelBuffer)
        let w = src.extent.width
        let h = src.extent.height

        // Step 1: Rotate content upright based on device orientation.
        let uprightT = VideoFrameProcessor.uprightTransform(
            for: orientation, sourceWidth: w, sourceHeight: h
        )
        let upright = uprightT.isIdentity ? src : src.transformed(by: uprightT)

        // Step 2: Aspect-fit and center if content doesn't match the canvas.
        let ciImage: CIImage
        if let fitT = VideoFrameProcessor.fitTransform(
            contentSize: upright.extent.size, canvasSize: landscapeSize
        ) {
            ciImage = upright.transformed(by: fitT)
        } else {
            ciImage = upright
        }

        return renderToSampleBuffer(ciImage, targetSize: landscapeSize, timingSource: sampleBuffer)
    }

    /// Renders a CIImage into a new CMSampleBuffer at the given size,
    /// preserving timing info from the source buffer.
    private func renderToSampleBuffer(
        _ ciImage: CIImage,
        targetSize: CGSize,
        timingSource: CMSampleBuffer
    ) -> CMSampleBuffer? {
        let outWidth = Int(targetSize.width)
        let outHeight = Int(targetSize.height)
        let outSize = CGSize(width: outWidth, height: outHeight)

        // (Re)create pool when output dimensions change
        if outSize != rotatedPoolSize {
            rotatedPoolSize = outSize
            let attrs: [String: Any] = [
                kCVPixelBufferWidthKey as String: outWidth,
                kCVPixelBufferHeightKey as String: outHeight,
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
            ]
            var pool: CVPixelBufferPool?
            CVPixelBufferPoolCreate(nil, nil, attrs as CFDictionary, &pool)
            rotatedBufferPool = pool
        }

        guard let pool = rotatedBufferPool else { return nil }

        var outputBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &outputBuffer)
        guard status == kCVReturnSuccess, let outputBuffer else { return nil }

        // Clear buffer to black — prevents stale pixel artifacts from pool recycling
        CVPixelBufferLockBaseAddress(outputBuffer, [])
        if let base = CVPixelBufferGetBaseAddress(outputBuffer) {
            memset(base, 0, CVPixelBufferGetBytesPerRow(outputBuffer) * outHeight)
        }
        CVPixelBufferUnlockBaseAddress(outputBuffer, [])

        ciContext.render(ciImage, to: outputBuffer)

        // Wrap in a new CMSampleBuffer with original timing
        var timingInfo = CMSampleTimingInfo()
        CMSampleBufferGetSampleTimingInfo(timingSource, at: 0, timingInfoOut: &timingInfo)

        var formatDescription: CMFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: nil,
            imageBuffer: outputBuffer,
            formatDescriptionOut: &formatDescription
        )
        guard let formatDescription else { return nil }

        var newSampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateForImageBuffer(
            allocator: nil,
            imageBuffer: outputBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDescription,
            sampleTiming: &timingInfo,
            sampleBufferOut: &newSampleBuffer
        )
        return newSampleBuffer
    }
}
