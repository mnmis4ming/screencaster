import SwiftUI

// MARK: - Theme

enum Theme {
    static let blue = Color(red: 0.27, green: 0.48, blue: 0.97)
    static let cardBackground = Color(.systemBackground)
    static let pageBackground = Color(red: 0.95, green: 0.96, blue: 0.98)
    static let labelSecondary = Color(.secondaryLabel)
    static let cardRadius: CGFloat = 20
    static let innerRadius: CGFloat = 12
}

// MARK: - ContentView (TabView root)

struct ContentView: View {
    var body: some View {
        TabView {
            StreamTab()
                .tabItem {
                    Image(systemName: "video.fill")
                    Text("Stream")
                }

            InfoTab()
                .tabItem {
                    Image(systemName: "info.circle.fill")
                    Text("Info")
                }
        }
        .tint(Theme.blue)
    }
}

// MARK: - Stream Tab

private struct StreamTab: View {
    @State private var streamURL: String = SharedConfig.streamURL
    @State private var videoBitrate: Double = Double(SharedConfig.videoBitrateMbps)
    @State private var selectedFps: Int = SharedConfig.fps

    var body: some View {
        ZStack {
            Theme.pageBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    topBar
                    broadcastHero
                    settingsCard
                }
                .padding(.bottom, 24)
            }
        }
    }

    // MARK: Top Bar

    private var topBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                Text("SCREEN")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 11))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(.darkGray))
            )

            Text("ScreenCaster")
                .font(.system(size: 20, weight: .bold, design: .rounded))

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // MARK: Broadcast Hero

    private var broadcastHero: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Theme.blue.opacity(0.18), Theme.blue.opacity(0.02)],
                            center: .center,
                            startRadius: 70,
                            endRadius: 120
                        )
                    )
                    .frame(width: 240, height: 240)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.35, green: 0.58, blue: 1.0),
                                Theme.blue,
                                Color(red: 0.20, green: 0.38, blue: 0.88),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 180, height: 180)
                    .shadow(color: Theme.blue.opacity(0.35), radius: 24, y: 8)

                VStack(spacing: 8) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 40, weight: .medium))
                        .foregroundStyle(.white)
                    Text("Start Broadcast")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.95))
                }

                BroadcastPickerView()
                    .frame(width: 180, height: 180)
                    .clipShape(Circle())
            }

            Text("Tap to begin capturing")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.labelSecondary)
        }
        .padding(.vertical, 4)
    }

    // MARK: Settings Card

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header
            HStack {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.blue)
                Text("Streaming Settings")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Spacer()
                Button("Reset") {
                    streamURL = SharedConfig.defaultStreamURL
                    SharedConfig.streamURL = SharedConfig.defaultStreamURL
                    videoBitrate = Double(SharedConfig.defaultVideoBitrateMbps)
                    SharedConfig.videoBitrateMbps = SharedConfig.defaultVideoBitrateMbps
                    selectedFps = SharedConfig.defaultFps
                    SharedConfig.fps = SharedConfig.defaultFps
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.blue)
            }

            // URL
            VStack(alignment: .leading, spacing: 6) {
                Text("URL")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.labelSecondary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                HStack(spacing: 10) {
                    Image(systemName: "link")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.labelSecondary)

                    TextField("rtmp:// or http:// URL", text: $streamURL)
                        .font(.system(size: 15))
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: streamURL) { newValue in
                            SharedConfig.streamURL = newValue
                        }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: Theme.innerRadius, style: .continuous)
                        .fill(Color(.tertiarySystemFill))
                )
            }

            // Bitrate
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("BITRATE")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.labelSecondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Spacer()
                    Text("\(Int(videoBitrate)) Mbps")
                        .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Theme.blue)
                }

                Slider(value: $videoBitrate, in: 1...15, step: 1)
                    .tint(Theme.blue)
                    .onChange(of: videoBitrate) { newValue in
                        SharedConfig.videoBitrateMbps = Int(newValue)
                    }
            }

            // FPS
            VStack(alignment: .leading, spacing: 8) {
                Text("FPS")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.labelSecondary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                HStack(spacing: 6) {
                    ForEach(SharedConfig.fpsOptions, id: \.self) { fps in
                        Button {
                            selectedFps = fps
                            SharedConfig.fps = fps
                        } label: {
                            Text("\(fps)")
                                .font(.system(size: 14, weight: .semibold, design: .rounded).monospacedDigit())
                                .frame(width: 44, height: 36)
                                .background(
                                    Capsule()
                                        .fill(selectedFps == fps ? Theme.blue : Color(.tertiarySystemFill))
                                )
                                .foregroundStyle(selectedFps == fps ? .white : .primary)
                        }
                    }
                    Spacer()
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(Theme.cardBackground)
                .shadow(color: .black.opacity(0.06), radius: 16, y: 4)
        )
        .padding(.horizontal, 16)
    }
}

// MARK: - Info Tab

private struct InfoTab: View {
    private var detectedProtocol: StreamProtocol {
        StreamProtocol(url: SharedConfig.streamURL)
    }

    var body: some View {
        ZStack {
            Theme.pageBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.blue)
                    Text("Stream Info")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 20)

                // Info card
                VStack(spacing: 0) {
                    InfoRow(icon: "globe", label: "Protocol", value: detectedProtocol.label)
                    Divider().padding(.leading, 56)
                    InfoRow(icon: "tv", label: "Resolution", value: "Device Native")
                    Divider().padding(.leading, 56)
                    InfoRow(icon: "speedometer", label: "FPS", value: "\(SharedConfig.fps)")
                    Divider().padding(.leading, 56)
                    InfoRow(icon: "arrow.up.circle", label: "Video Bitrate", value: "\(SharedConfig.videoBitrateMbps) Mbps")
                    Divider().padding(.leading, 56)
                    InfoRow(icon: "waveform", label: "Audio", value: audioLabel)
                    Divider().padding(.leading, 56)
                    InfoRow(icon: "cpu", label: "Codec", value: "H.264 High")
                }
                .background(
                    RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                        .fill(Theme.cardBackground)
                        .shadow(color: .black.opacity(0.06), radius: 16, y: 4)
                )
                .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                .padding(.horizontal, 16)

                Spacer()
            }
        }
    }

    private var audioLabel: String {
        switch detectedProtocol {
        case .rtmp: return "AAC 192 kbps"
        case .whip: return "Opus 128 kbps"
        }
    }
}

// MARK: - InfoRow

private struct InfoRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.blue)
                .frame(width: 24)
            Text(label)
                .font(.system(size: 15))
                .foregroundStyle(.primary)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.labelSecondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 13)
    }
}

#Preview {
    ContentView()
}
