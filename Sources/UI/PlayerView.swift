import SwiftUI

struct PlayerView: View {
    @ObservedObject var controller: PlaybackController
    @ObservedObject var store: ChannelStore
    let webView: WebViewPlayerService
    var settings: AppSettings
    let onClose: () -> Void

    @State private var overlayVisible = true

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
                    onClose: onClose
                )
                .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { withAnimation { overlayVisible.toggle() } }
        .gesture(
            DragGesture(minimumDistance: 30).onEnded { value in
                if value.translation.height < -30 { controller.surf(.next) }
                else if value.translation.height > 30 { controller.surf(.previous) }
            }
        )
        .statusBarHidden(true)
    }
}
