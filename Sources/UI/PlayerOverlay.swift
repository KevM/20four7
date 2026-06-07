import SwiftUI

struct PlayerOverlay: View {
    @ObservedObject var controller: PlaybackController
    let showClock: Bool
    let dimOpacity: Double
    let onSurf: (SurfDirection) -> Void
    let onToggleFavorite: () -> Void
    let isFavorite: Bool
    let onStartSleep: () -> Void
    @Binding var fillScreen: Bool
    let onInteraction: () -> Void
    let onClose: () -> Void
    let onGoLive: () -> Void

    let activeTag: String?

    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private func formatTime(_ time: TimeInterval) -> String {
        let roundedTime = max(0, ceil(time))
        let mins = Int(roundedTime) / 60
        let secs = Int(roundedTime) % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var m: LayoutMetrics { LayoutMetrics(hSizeClass) }

    var body: some View {
        ZStack {
            Color.black.opacity(dimOpacity).ignoresSafeArea().allowsHitTesting(false)

            VStack {
                HStack {
                    if let c = controller.currentChannel {
                        VStack(alignment: .leading, spacing: m.overlayTitleStackSpacing) {
                            if controller.isCurrentlyLive {
                                // YouTube-style live indicator: a red dot + white
                                // "LIVE" at the edge. When behind, the color drains
                                // to gray and tapping it jumps back to live.
                                Button {
                                    onInteraction()
                                    onGoLive()
                                } label: {
                                    (Text("●").foregroundColor(controller.isBehindLive ? .gray : .red)
                                     + Text(" LIVE").foregroundColor(controller.isBehindLive ? .gray : .white))
                                        .font(m.overlayLiveFont)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .disabled(!controller.isBehindLive)
                            }
                            Text(c.title)
                                .font(m.overlayTitleFont)
                            if controller.isAutoSurfActive, let remaining = controller.autoSurfTimeRemaining {
                                HStack(spacing: 6) {
                                    Text(activeTag.map { "Tag surfing: \($0)" } ?? "Tag surfing")
                                        .font(.caption.bold())
                                    Image(systemName: "timer")
                                        .font(.caption)
                                    Text(formatTime(remaining))
                                        .font(.caption.bold())
                                }
                            }
                        }
                        .padding(.horizontal, m.overlayCardHPadding)
                        .padding(.vertical, m.overlayCardVPadding)
                        .background(.ultraThinMaterial)
                        .cornerRadius(m.overlayCardCorner)
                        .overlay(
                            RoundedRectangle(cornerRadius: m.overlayCardCorner)
                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                        )
                    }
                    Spacer()
                }
                .padding()

                Spacer()

                Spacer()

                if showClock {
                    Text(now, format: .dateTime.hour().minute())
                        .font(.system(size: 56, weight: .thin))
                        .onReceive(timer) { now = $0 }
                }

                HStack(spacing: m.controlsSpacing) {
                    Button {
                        onInteraction()
                        controller.state == .playing ? controller.pauseFromUI() : controller.playFromUI()
                    } label: {
                        Image(systemName: controller.state == .playing ? "pause.fill" : "play.fill")
                            .frame(width: m.controlSize, height: m.controlSize)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        onInteraction()
                        onToggleFavorite()
                    } label: {
                        Image(systemName: isFavorite ? "star.fill" : "star")
                            .frame(width: m.controlSize, height: m.controlSize)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        onInteraction()
                        onStartSleep()
                    } label: {
                        Image(systemName: controller.sleepTimerActive ? "moon.zzz.fill" : "moon.zzz")
                            .frame(width: m.controlSize, height: m.controlSize)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        onInteraction()
                        fillScreen.toggle()
                    } label: {
                        Image(systemName: fillScreen ? "aspectratio.fill" : "aspectratio")
                            .frame(width: m.controlSize, height: m.controlSize)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Divider()
                        .frame(height: m.controlSize)
                        .overlay(Color.white.opacity(0.25))

                    Button(action: onClose) {
                        Image(systemName: "chevron.down")
                            .frame(width: m.controlSize, height: m.controlSize)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .font(m.controlsFont)
                .padding(.horizontal, m.controlsHPadding)
                .padding(.vertical, m.controlsVPadding)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
                .padding(.bottom, m.controlsBottomPadding)
            }
            .foregroundStyle(.white)

            if controller.showsOfflineState {
                VStack(spacing: 12) {
                    Image(systemName: "wifi.slash").font(.largeTitle)
                    Text("This stream is offline").font(.headline)
                    Button("Next channel") { onSurf(.next) }
                        .buttonStyle(.borderedProminent)
                }
                .padding(24)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .foregroundStyle(.white)
            }
        }
    }
}
