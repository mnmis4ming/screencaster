import SwiftUI

struct ContentView: View {
    @State private var streamURL: String = SharedConfig.streamURL
    @State private var videoBitrate: Double = Double(SharedConfig.videoBitrateMbps)
    @State private var selectedFps: Int = SharedConfig.fps

    private var detectedProtocol: StreamProtocol {
        StreamProtocol(url: streamURL)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(.systemBackground), Color(.secondarySystemBackground)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 32) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 48, weight: .light))
                            .foregroundStyle(.tint)

                        Text("ScreenCaster")
                            .font(.largeTitle.bold())

                        Text("Stream your screen via \(detectedProtocol.label)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 40)

                    // Stream URL input
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Stream Server", systemImage: "link")
                            .font(.headline)

                        TextField("rtmp:// or http:// URL", text: $streamURL)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding()
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .onChange(of: streamURL, perform: { newValue in
                                SharedConfig.streamURL = newValue
                            })

                        Text(protocolHint)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal)

                    // Video bitrate slider
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Video Bitrate", systemImage: "arrow.up.circle")
                            .font(.headline)

                        HStack {
                            Text("1")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Slider(value: $videoBitrate, in: 1...15, step: 1)
                                .onChange(of: videoBitrate) { newValue in
                                    SharedConfig.videoBitrateMbps = Int(newValue)
                                }
                            Text("15")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text("\(Int(videoBitrate)) Mbps")
                            .font(.subheadline.weight(.medium).monospacedDigit())
                            .foregroundStyle(.tint)
                    }
                    .padding(.horizontal)

                    // FPS picker
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Frame Rate", systemImage: "speedometer")
                            .font(.headline)

                        HStack(spacing: 8) {
                            ForEach(SharedConfig.fpsOptions, id: \.self) { fps in
                                Button {
                                    selectedFps = fps
                                    SharedConfig.fps = fps
                                } label: {
                                    Text("\(fps)")
                                        .font(.subheadline.weight(.medium).monospacedDigit())
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(selectedFps == fps ? Color.accentColor : Color(.tertiarySystemFill))
                                        .foregroundStyle(selectedFps == fps ? .white : .primary)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        }
                    }
                    .padding(.horizontal)

                    // Broadcast button
                    VStack(spacing: 12) {
                        BroadcastPickerView()
                            .frame(width: 120, height: 120)
                            .background(
                                ZStack {
                                    Circle()
                                        .fill(.tint.opacity(0.15))

                                    Circle()
                                        .fill(.tint)
                                        .frame(width: 88, height: 88)
                                        .shadow(color: .accentColor.opacity(0.4), radius: 12, y: 4)

                                    Image(systemName: "record.circle")
                                        .font(.system(size: 36, weight: .medium))
                                        .foregroundStyle(.white)
                                }
                            )

                        Text("Tap to Broadcast")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }

                    // Stream info card
                    VStack(spacing: 0) {
                        InfoRow(icon: "globe", label: "Protocol", value: detectedProtocol.label)
                        Divider().padding(.leading, 44)
                        InfoRow(icon: "tv", label: "Resolution", value: "Device Native")
                        Divider().padding(.leading, 44)
                        InfoRow(icon: "speedometer", label: "FPS", value: "\(selectedFps)")
                        Divider().padding(.leading, 44)
                        InfoRow(icon: "arrow.up.circle", label: "Video Bitrate", value: "\(Int(videoBitrate)) Mbps")
                        Divider().padding(.leading, 44)
                        InfoRow(icon: "waveform", label: "Audio", value: audioLabel)
                        Divider().padding(.leading, 44)
                        InfoRow(icon: "cpu", label: "Codec", value: "H.264 High")
                    }
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)

                    Spacer(minLength: 20)
                }
            }
        }
    }

    private var protocolHint: String {
        switch detectedProtocol {
        case .rtmp:
            return "Using RTMP — rtmp:// detected"
        case .whip:
            return "Using WebRTC (WHIP) — http(s):// detected"
        }
    }

    private var audioLabel: String {
        switch detectedProtocol {
        case .rtmp:
            return "AAC 192 kbps"
        case .whip:
            return "Opus 128 kbps"
        }
    }
}

private struct InfoRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 28)
                .foregroundStyle(.tint)
            Text(label)
                .foregroundStyle(.primary)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

#Preview {
    ContentView()
}
