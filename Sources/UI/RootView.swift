import SwiftUI
import WebKit

struct RootView: View {
    @ObservedObject var env: AppEnvironment
    @State private var playing: Channel?
    @State private var showAddChannel = false

    var body: some View {
        NavigationStack {
            GuideView(store: env.channelStore) { channel in
                startPlaying(channel)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { SettingsView(localStore: env.localStore, store: env.channelStore) } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAddChannel = true } label: { Image(systemName: "plus") }
                }
            }
        }
        .fullScreenCover(item: $playing) { _ in
            PlayerView(
                controller: env.controller, store: env.channelStore, webView: env.player,
                settings: env.localStore.settings(),
                onClose: {
                    playing = nil
                    env.channelStore.startBackgroundScan()
                }
            )
        }
        .sheet(isPresented: $showAddChannel) {
            AddChannelView(store: env.channelStore, localStore: env.localStore) {
                Task { await env.channelStore.refresh() }
            }
        }
        .task { await maybeAutoResume() }
        .background(
            Group {
                if let scannerWebView = env.channelStore.scannerWebView {
                    ScannerWebViewRepresentable(webView: scannerWebView)
                        .frame(width: 1, height: 1)
                        .opacity(0.01)
                        .allowsHitTesting(false)
                }
            }
        )
    }

    @MainActor
    private func startPlaying(_ channel: Channel) {
        env.controller.setLineup(env.channelStore.filteredChannels)
        env.controller.play(channelID: channel.id)
        playing = channel
    }

    @MainActor
    private func maybeAutoResume() async {
        try? await Task.sleep(nanoseconds: 500_000_000)
        await env.channelStore.refresh()
        guard env.localStore.settings().autoResume,
              let lastID = env.localStore.lastWatchedChannelID(),
              let channel = env.channelStore.channels.first(where: { $0.id == lastID }) else { return }
        startPlaying(channel)
    }
}

struct ScannerWebViewRepresentable: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView {
        webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
