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

    private var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    var body: some View {
        ZStack {
            Color.black.opacity(dimOpacity).ignoresSafeArea().allowsHitTesting(false)

            VStack {
                HStack {
                    if let c = controller.currentChannel {
                        VStack(alignment: .leading, spacing: isPad ? 6 : 4) {
                            if controller.isCurrentlyLive {
                                Text("● LIVE")
                                    .font(isPad ? .subheadline.bold() : .caption.bold())
                                    .foregroundStyle(.red)
                            }
                            HStack(alignment: .center, spacing: isPad ? 14 : 10) {
                                Text(c.title)
                                    .font(.system(size: isPad ? 22 : 17, weight: .bold))
                                Button(action: onClose) {
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: isPad ? 14 : 12, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(width: isPad ? 36 : 28, height: isPad ? 36 : 28)
                                        .background(Color.black.opacity(0.25))
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                            }
                            if controller.isAutoSurfActive, let tag = activeTag {
                                Text("Surfing: \(tag)")
                                    .font(.system(size: isPad ? 14 : 11, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, isPad ? 10 : 8)
                                    .padding(.vertical, isPad ? 6 : 4)
                                    .background(Color.black.opacity(0.35))
                                    .cornerRadius(isPad ? 10 : 8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: isPad ? 10 : 8)
                                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                    )
                                    .padding(.top, 2)
                            }
                        }
                        .padding(.horizontal, isPad ? 18 : 14)
                        .padding(.vertical, isPad ? 14 : 10)
                        .background(.ultraThinMaterial)
                        .cornerRadius(isPad ? 20 : 16)
                        .overlay(
                            RoundedRectangle(cornerRadius: isPad ? 20 : 16)
                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                        )
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

                HStack(spacing: isPad ? 36 : 22) {
                    Button {
                        onInteraction()
                        controller.state == .playing ? controller.pauseFromUI() : controller.playFromUI()
                    } label: {
                        Image(systemName: controller.state == .playing ? "pause.fill" : "play.fill")
                            .frame(width: isPad ? 64 : 44, height: isPad ? 64 : 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        onInteraction()
                        onToggleFavorite()
                    } label: {
                        Image(systemName: isFavorite ? "star.fill" : "star")
                            .frame(width: isPad ? 64 : 44, height: isPad ? 64 : 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        onInteraction()
                        onStartSleep()
                    } label: {
                        Image(systemName: controller.sleepTimerActive ? "moon.zzz.fill" : "moon.zzz")
                            .frame(width: isPad ? 64 : 44, height: isPad ? 64 : 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        onInteraction()
                        fillScreen.toggle()
                    } label: {
                        Image(systemName: fillScreen ? "aspectratio.fill" : "aspectratio")
                            .frame(width: isPad ? 64 : 44, height: isPad ? 64 : 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .font(isPad ? .system(size: 32) : .title2)
                .padding(.horizontal, isPad ? 24 : 16)
                .padding(.vertical, isPad ? 12 : 8)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
                .padding(.bottom, isPad ? 40 : 24)
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
