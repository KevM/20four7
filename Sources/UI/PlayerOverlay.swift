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

    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color.black.opacity(dimOpacity).ignoresSafeArea().allowsHitTesting(false)

            VStack {
                HStack {
                    VStack(alignment: .leading) {
                        if let c = controller.currentChannel {
                            if c.isLiveExpected { Text("● LIVE").font(.caption.bold()).foregroundStyle(.red) }
                            Text(c.title).font(.headline)
                        }
                    }
                    Spacer()
                    Button(action: onClose) { Image(systemName: "chevron.down") }
                }
                .padding()

                Spacer()

                // Surf affordance
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Button { onInteraction(); onSurf(.previous) } label: { Image(systemName: "chevron.up") }
                        Text("SURF").font(.caption2)
                        Button { onInteraction(); onSurf(.next) } label: { Image(systemName: "chevron.down") }
                    }
                    .padding(.trailing)
                }

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
                    }
                    Button {
                        onInteraction()
                        onToggleFavorite()
                    } label: {
                        Image(systemName: isFavorite ? "star.fill" : "star")
                    }
                    Button {
                        onInteraction()
                        onStartSleep()
                    } label: {
                        Image(systemName: controller.sleepTimerActive ? "moon.zzz.fill" : "moon.zzz")
                    }
                    Button {
                        onInteraction()
                        fillScreen.toggle()
                    } label: {
                        Image(systemName: fillScreen ? "aspectratio.fill" : "aspectratio")
                    }
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
