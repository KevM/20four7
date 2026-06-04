import SwiftUI

struct RootView: View {
    @ObservedObject var env: AppEnvironment
    @ObservedObject private var store: ChannelStore
    @State private var playing: Channel?
    @State private var showAddChannel = false
    @State private var showingTagPicker = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var pausedForBackground = false
    @State private var wasPlayingAtBackground = false

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
                    .accessibilityLabel(store.selectedTagIDs.isEmpty
                                        ? "Filter" : "Filter (\(store.selectedTagIDs.count) active)")
                }
                if !store.selectedTagIDs.isEmpty && !store.filteredChannels.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            if let firstChannel = store.filteredChannels.first {
                                startPlaying(firstChannel, autoSurf: true)
                            }
                        } label: {
                            Image(systemName: "play.square.stack.fill")
                        }
                        .accessibilityLabel("Auto-Surf")
                    }
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
                    env.controller.stop()
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
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                // Only a real background pauses; transient .inactive overlays
                // (Control Center, Notification Center, app-switcher peek) do not.
                let wasPlaying = playing != nil && !env.controller.isManuallyPaused
                wasPlayingAtBackground = wasPlaying
                env.localStore.setResumeWasPlaying(wasPlaying)
                env.controller.pauseForBackground()
                pausedForBackground = true
            case .active:
                guard pausedForBackground else { return }
                pausedForBackground = false
                if env.localStore.settings().autoResume && wasPlayingAtBackground {
                    env.controller.playFromUI()
                }
            default:
                break
            }
        }
    }

    @MainActor
    private func startPlaying(_ channel: Channel, autoSurf: Bool = false, startTime: Double = 0) {
        var lineup = store.filteredChannels
        if !lineup.contains(where: { $0.id == channel.id }) {
            lineup.append(channel)
        }
        env.controller.setLineup(lineup)
        if autoSurf {
            env.controller.startAutoSurf(interval: Double(env.localStore.settings().defaultAutoSurfMinutes) * 60)
        }
        env.controller.play(channelID: channel.id, startTime: startTime)
        playing = channel
    }

    @MainActor
    private func maybeAutoResume() async {
        try? await Task.sleep(nanoseconds: 500_000_000)
        await store.refresh()
        let resume = env.localStore.resumeState()
        guard env.localStore.settings().autoResume,
              resume.wasPlaying,
              let lastID = resume.channelID,
              let channel = store.channels.first(where: { $0.id == lastID }) else { return }
        startPlaying(channel, autoSurf: resume.isAutoSurf)
    }
}
