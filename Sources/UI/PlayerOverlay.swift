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

    let activeTag: String?

    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private func formatTime(_ time: TimeInterval) -> String {
        let roundedTime = max(0, ceil(time))
        let mins = Int(roundedTime) / 60
        let secs = Int(roundedTime) % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(dimOpacity).ignoresSafeArea().allowsHitTesting(false)

            VStack {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        if let c = controller.currentChannel {
                            if controller.isCurrentlyLive { Text("● LIVE").font(.caption.bold()).foregroundStyle(.red) }
                            HStack(alignment: .center, spacing: 10) {
                                Text(c.title).font(.headline)
                                Button(action: onClose) {
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 28, height: 28)
                                        .background(Color.black.opacity(0.35))
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                            }
                            if controller.isAutoSurfActive, let tag = activeTag {
                                Text("Surfing: \(tag)")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Spacer()

                    if controller.isAutoSurfActive, let remaining = controller.autoSurfTimeRemaining {
                        HStack(spacing: 6) {
                            Image(systemName: "timer")
                                .font(.caption)
                            Text("Surfing in \(formatTime(remaining))")
                                .font(.caption.bold())
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                        )
                        .layoutPriority(1)
                    }
                }
                .padding()

                Spacer()

                Spacer()

                if showClock {
                    Text(now, format: .dateTime.hour().minute())
                        .font(.system(size: 56, weight: .thin))
                        .onReceive(timer) { now = $0 }
                }

                HStack(spacing: 22) {
                    Button {
                        onInteraction()
                        controller.state == .playing ? controller.pauseFromUI() : controller.playFromUI()
                    } label: {
                        Image(systemName: controller.state == .playing ? "pause.fill" : "play.fill")
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        onInteraction()
                        onToggleFavorite()
                    } label: {
                        Image(systemName: isFavorite ? "star.fill" : "star")
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        onInteraction()
                        onStartSleep()
                    } label: {
                        Image(systemName: controller.sleepTimerActive ? "moon.zzz.fill" : "moon.zzz")
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        onInteraction()
                        fillScreen.toggle()
                    } label: {
                        Image(systemName: fillScreen ? "aspectratio.fill" : "aspectratio")
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .font(.title2)
                .padding(.bottom, 24)
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
