import SwiftUI

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
                    NavigationLink { SettingsView(localStore: env.localStore) } label: {
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
                onClose: { playing = nil }
            )
        }
        .sheet(isPresented: $showAddChannel) {
            AddChannelView(store: env.channelStore, localStore: env.localStore) {
                Task { await env.channelStore.refresh() }
            }
        }
        .task { await maybeAutoResume() }
    }

    private func startPlaying(_ channel: Channel) {
        env.controller.setLineup(env.channelStore.filteredChannels)
        env.controller.play(channelID: channel.id)
        playing = channel
    }

    private func maybeAutoResume() async {
        await env.channelStore.refresh()
        guard env.localStore.settings().autoResume,
              let lastID = env.localStore.lastWatchedChannelID(),
              let channel = env.channelStore.channels.first(where: { $0.id == lastID }) else { return }
        startPlaying(channel)
    }
}
