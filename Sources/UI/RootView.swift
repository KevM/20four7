import SwiftUI
import WebKit

struct RootView: View {
    @ObservedObject var env: AppEnvironment
    @ObservedObject private var store: ChannelStore
    @State private var playing: Channel?
    @State private var showAddChannel = false
    @State private var copiedPlaylist = false

    init(env: AppEnvironment) {
        self.env = env
        self.store = env.channelStore
    }

    var body: some View {
        NavigationStack {
            GuideView(store: store) { channel in
                startPlaying(channel)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { SettingsView(localStore: env.localStore, store: store) } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if let url = store.filteredPlaylistURL {
                            UIPasteboard.general.string = url.absoluteString
                            withAnimation {
                                copiedPlaylist = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                withAnimation {
                                    copiedPlaylist = false
                                }
                            }
                        }
                    } label: {
                        if copiedPlaylist {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else {
                            Image(systemName: "play.rectangle.on.rectangle")
                        }
                    }
                    .disabled(store.filteredPlaylistURL == nil)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAddChannel = true } label: { Image(systemName: "plus") }
                }
            }
        }
        .fullScreenCover(item: $playing) { _ in
            PlayerView(
                controller: env.controller, store: store, webView: env.player,
                settings: env.localStore.settings(),
                onClose: {
                    playing = nil
                    store.startBackgroundScan()
                }
            )
        }
        .sheet(isPresented: $showAddChannel) {
            AddChannelView(store: store, localStore: env.localStore) {
                Task { await store.refresh() }
            }
        }
        .task { await maybeAutoResume() }
        .background(
            Group {
                if let scannerWebView = store.scannerWebView {
                    ScannerWebViewRepresentable(webView: scannerWebView)
                        .frame(width: 1, height: 1)
                        .opacity(0.01)
                        .allowsHitTesting(false)
                }
            }
        )
        .overlay(alignment: .top) {
            if copiedPlaylist {
                Text("Playlist URL copied to clipboard!")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    .background(Color.blue.opacity(0.9))
                    .cornerRadius(20)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 12)
            }
        }
    }

    @MainActor
    private func startPlaying(_ channel: Channel) {
        env.controller.setLineup(store.filteredChannels)
        env.controller.play(channelID: channel.id)
        playing = channel
    }

    @MainActor
    private func maybeAutoResume() async {
        try? await Task.sleep(nanoseconds: 500_000_000)
        await store.refresh()
        guard env.localStore.settings().autoResume,
              let lastID = env.localStore.lastWatchedChannelID(),
              let channel = store.channels.first(where: { $0.id == lastID }) else { return }
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
