import SwiftUI

struct RootView: View {
    @ObservedObject var env: AppEnvironment
    @ObservedObject private var store: ChannelStore
    @State private var playing: Channel?
    @State private var showAddChannel = false
    @State private var copiedPlaylist = false
    @State private var showingTagPicker = false

    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var m: LayoutMetrics { LayoutMetrics(hSizeClass) }

    init(env: AppEnvironment) {
        self.env = env
        self.store = env.channelStore
    }

    var body: some View {
        NavigationStack {
            GuideView(store: store, onSelect: { channel in
                startPlaying(channel)
            }, onAutoSurf: {
                if let firstChannel = store.filteredChannels.first {
                    startAutoSurfing(firstChannel)
                }
            })
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { SettingsView(localStore: env.localStore, store: store) } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingTagPicker = true } label: {
                        Image(systemName: store.selectedTagIDs.isEmpty
                              ? "line.3.horizontal.decrease.circle"
                              : "line.3.horizontal.decrease.circle.fill")
                    }
                    .tint(store.selectedTagIDs.isEmpty ? nil : .blue)
                    .accessibilityLabel(store.selectedTagIDs.isEmpty
                                        ? "Filter" : "Filter (\(store.selectedTagIDs.count) active)")
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
                    env.controller.stopAutoSurf()
                }
            )
        }
        .sheet(isPresented: $showAddChannel) {
            YouTubeBrowserView(
                store: store,
                localStore: env.localStore,
                onSaved: {
                    Task { await store.refresh() }
                },
                onWatchNow: { channel, startTime in
                    showAddChannel = false
                    Task {
                        await store.refresh()
                        try? await Task.sleep(nanoseconds: 100_000_000)
                        startPlaying(channel, startTime: startTime)
                    }
                }
            )
        }
        .sheet(isPresented: $showingTagPicker) {
            TagPickerSheetView(store: store, isParentWide: m.wide)
                .presentationDetents(m.wide ? [.large] : [.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .task { await maybeAutoResume() }
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
    private func startPlaying(_ channel: Channel, startTime: Double = 0) {
        var lineup = store.filteredChannels
        if !lineup.contains(where: { $0.id == channel.id }) {
            lineup.append(channel)
        }
        env.controller.setLineup(lineup)
        env.controller.play(channelID: channel.id, startTime: startTime)
        playing = channel
    }

    @MainActor
    private func startAutoSurfing(_ channel: Channel) {
        env.controller.setLineup(store.filteredChannels)
        env.controller.startAutoSurf(interval: Double(env.localStore.settings().defaultAutoSurfMinutes) * 60)
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
