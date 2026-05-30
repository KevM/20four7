import SwiftUI

struct PlayerView: View {
    @ObservedObject var controller: PlaybackController
    @ObservedObject var store: ChannelStore
    let webView: WebViewPlayerService
    var settings: AppSettings
    let onClose: () -> Void

    @State private var overlayVisible = true
    @State private var fillScreen = true
    @State private var hideTask: Task<Void, Never>? = nil

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            PlayerWebView(webView: webView.webView).ignoresSafeArea()

            if overlayVisible {
                PlayerOverlay(
                    controller: controller,
                    showClock: settings.showClockOverlay,
                    dimOpacity: Double(settings.dimLevelRaw) * 0.2,
                    onSurf: { controller.surf($0) },
                    onToggleFavorite: { if let c = controller.currentChannel { store.toggleFavorite(c) } },
                    isFavorite: controller.currentChannel.map { store.isFavorite($0) } ?? false,
                    onStartSleep: { controller.startSleepTimer(seconds: Double(settings.defaultSleepMinutes) * 60) },
                    fillScreen: $fillScreen,
                    onInteraction: { resetHideTimer() },
                    onClose: onClose
                )
                .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation {
                overlayVisible.toggle()
                if overlayVisible {
                    resetHideTimer()
                } else {
                    hideTask?.cancel()
                }
            }
        }
        .gesture(
            DragGesture(minimumDistance: 30).onEnded { value in
                resetHideTimer()
                if value.translation.height < -30 { controller.surf(.next) }
                else if value.translation.height > 30 { controller.surf(.previous) }
            }
        )
        .statusBarHidden(true)
        .onAppear {
            webView.setAspectCover(fillScreen)
            if overlayVisible {
                resetHideTimer()
            }
        }
        .onDisappear {
            hideTask?.cancel()
        }
        .onChange(of: fillScreen) {
            webView.setAspectCover(fillScreen)
        }
    }

    private func resetHideTimer() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
            guard !Task.isCancelled else { return }
            withAnimation {
                overlayVisible = false
            }
        }
    }
}
