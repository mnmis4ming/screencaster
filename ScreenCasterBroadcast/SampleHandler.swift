import CoreImage
import HaishinKit
import ReplayKit
import RTCHaishinKit
import RTMPHaishinKit
import VideoToolbox

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
            let orientation = Self.orientation(from: sampleBuffer)

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
    /// - Portrait (.up): scales and centers with black pillarbox bars.
    /// - Landscape (.left/.right): rotates to correct orientation.
    private func processedVideoBuffer(
        _ sampleBuffer: CMSampleBuffer,
        orientation: CGImagePropertyOrientation
    ) -> CMSampleBuffer? {
        guard let pixelBuffer = sampleBuffer.imageBuffer, landscapeSize != .zero else { return nil }

        let ciImage: CIImage

        if orientation == .up {
            // Portrait: scale to fit landscape height, center with black bars
            let src = CIImage(cvPixelBuffer: pixelBuffer)
            let scale = landscapeSize.height / src.extent.height
            var scaled = src.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            let offsetX = (landscapeSize.width - scaled.extent.width) / 2
            scaled = scaled.transformed(by: CGAffineTransform(translationX: offsetX, y: 0))
            let black = CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: landscapeSize))
            ciImage = scaled.composited(over: black)
        } else {
            // Landscape: rotate. Swap left/right because oriented() converts TO .up,
            // but we want landscape output.
            let corrected: CGImagePropertyOrientation
            switch orientation {
            case .left:  corrected = .right
            case .right: corrected = .left
            default:     corrected = orientation
            }
            var img = CIImage(cvPixelBuffer: pixelBuffer)
            img = img.oriented(corrected)
            ciImage = img
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

        // Normalize extent origin to (0,0) before rendering
        let normalized = ciImage.transformed(
            by: CGAffineTransform(translationX: -ciImage.extent.origin.x,
                                  y: -ciImage.extent.origin.y)
        )
        ciContext.render(normalized, to: outputBuffer)

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
