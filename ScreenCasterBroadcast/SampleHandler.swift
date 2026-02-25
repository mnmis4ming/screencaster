import CoreImage
import HaishinKit
import MediaPlayer
import ReplayKit
import RTCHaishinKit
import RTMPHaishinKit
import VideoToolbox

final class SampleHandler: RPBroadcastSampleHandler, @unchecked Sendable {
    private var slider: UISlider?
    private var session: (any Session)?
    private var mixer = MediaMixer(captureSessionMode: .manual, multiTrackAudioMixingEnabled: true)

    // Rotation handling
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private var rotatedBufferPool: CVPixelBufferPool?
    private var rotatedPoolSize: CGSize = .zero
    private var encoderConfigured = false
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

        // Hack to read system volume for adjusting app audio level
        DispatchQueue.main.async {
            let volumeView = MPVolumeView(frame: .zero)
            if let slider = volumeView.subviews.compactMap({ $0 as? UISlider }).first {
                self.slider = slider
            }
        }
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        switch sampleBufferType {
        case .video:
            let orientation = Self.orientation(from: sampleBuffer)
            let needsRotation = (orientation != .up)

            // Configure encoder once — always use landscape dimensions
            if !encoderConfigured, let dimensions = sampleBuffer.formatDescription?.dimensions {
                let w = CGFloat(dimensions.width)
                let h = CGFloat(dimensions.height)
                // Always landscape: wider side as width
                let outputSize = CGSize(width: max(w, h), height: min(w, h))
                encoderConfigured = true
                Task {
                    var videoSettings = await session?.stream.videoSettings
                    videoSettings?.videoSize = outputSize
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

            if needsRotation, let rotated = rotatedSampleBuffer(sampleBuffer, orientation: orientation) {
                Task { await mixer.append(rotated) }
            } else {
                Task { await mixer.append(sampleBuffer) }
            }

        case .audioMic:
            if sampleBuffer.dataReadiness == .ready {
                Task { await mixer.append(sampleBuffer, track: 0) }
            }
        case .audioApp:
            Task { @MainActor in
                if let volume = slider?.value {
                    var audioMixerSettings = await mixer.audioMixerSettings
                    audioMixerSettings.tracks[1] = .default
                    audioMixerSettings.tracks[1]?.volume = volume * 0.5
                    await mixer.setAudioMixerSettings(audioMixerSettings)
                }
            }
            if sampleBuffer.dataReadiness == .ready {
                Task { await mixer.append(sampleBuffer, track: 1) }
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

    /// Rotates the pixel buffer using CIImage (GPU-accelerated) and wraps it
    /// back into a CMSampleBuffer with the original timing info preserved.
    private func rotatedSampleBuffer(
        _ sampleBuffer: CMSampleBuffer,
        orientation: CGImagePropertyOrientation
    ) -> CMSampleBuffer? {
        guard let pixelBuffer = sampleBuffer.imageBuffer else { return nil }

        // Apply orientation transform via CIImage (GPU path).
        // CIImage.oriented() converts FROM the given orientation TO .up (portrait),
        // but our encoder expects landscape output. Swap left/right so the rotation
        // goes in the correct direction for landscape.
        let corrected: CGImagePropertyOrientation
        switch orientation {
        case .left:  corrected = .right
        case .right: corrected = .left
        default:     corrected = orientation
        }
        var ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        ciImage = ciImage.oriented(corrected)

        let outWidth = Int(ciImage.extent.width)
        let outHeight = Int(ciImage.extent.height)
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

        var rotatedBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &rotatedBuffer)
        guard status == kCVReturnSuccess, let rotatedBuffer else { return nil }

        // CIImage extent may have a non-zero origin after oriented(); shift to (0,0)
        let translated = ciImage.transformed(
            by: CGAffineTransform(translationX: -ciImage.extent.origin.x,
                                  y: -ciImage.extent.origin.y)
        )
        ciContext.render(translated, to: rotatedBuffer)

        // Wrap in a new CMSampleBuffer with original timing
        var timingInfo = CMSampleTimingInfo()
        CMSampleBufferGetSampleTimingInfo(sampleBuffer, at: 0, timingInfoOut: &timingInfo)

        var formatDescription: CMFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: nil,
            imageBuffer: rotatedBuffer,
            formatDescriptionOut: &formatDescription
        )
        guard let formatDescription else { return nil }

        var newSampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateForImageBuffer(
            allocator: nil,
            imageBuffer: rotatedBuffer,
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
