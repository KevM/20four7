import SwiftUI

/// Drives the add-channel sheet. Carrying the optional seed query *as the
/// presentation item* (rather than a separate `@State` read inside an
/// `isPresented:` sheet) guarantees the sheet is built with the right query —
/// `.sheet(item:)` snapshots the value atomically with presentation.
private struct AddFlowRequest: Identifiable {
    let id = UUID()
    /// Seed query for the YouTube search, or nil for the default landing search.
    let searchQuery: String?
}

struct RootView: View {
    @ObservedObject var env: AppEnvironment
    @ObservedObject private var store: ChannelStore
    @State private var playing: Channel?
    @State private var addFlow: AddFlowRequest? = nil
    @State private var showingTagPicker = false
    @State private var isSearchPresented = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var pausedForBackground = false

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
            }, onSearchYouTube: { query in
                addFlow = AddFlowRequest(searchQuery: query)
            })
            .searchable(text: $store.searchQuery, isPresented: $isSearchPresented, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search your Guide")
            .toolbar {
                // Escape exits search the way it dismisses a sheet. `.searchable`
                // doesn't bind Escape on its own, and on Mac it omits the Cancel
                // button that iOS shows automatically — so on Mac only we add a
                // visible Cancel carrying the standard cancel-action (Escape)
                // shortcut. Shown whenever there's a search to exit.
                if ProcessInfo.processInfo.isiOSAppOnMac,
                   isSearchPresented || !store.searchQuery.isEmpty {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            store.searchQuery = ""
                            isSearchPresented = false
                        }
                        .keyboardShortcut(.cancelAction)
                    }
                }
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
                    Button {
                        addFlow = AddFlowRequest(searchQuery: nil)
                    } label: {
                        Image(systemName: "plus")
                    }
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
                    env.localStore.setResumeWasPlaying(false)
                }
            )
        }
        .fullScreenCover(item: $addFlow) { request in
            YouTubeBrowserView(
                store: store,
                localStore: env.localStore,
                initialSearchQuery: request.searchQuery,
                onSaved: {
                    Task { await store.refresh() }
                },
                onWatchNow: { channel, startTime in
                    addFlow = nil
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
                env.localStore.setResumeWasPlaying(wasPlaying)
                env.controller.pauseForBackground()
                pausedForBackground = true
            case .active:
                guard pausedForBackground else { return }
                pausedForBackground = false
                // The controller owns the resume-vs-pause decision; on foreground
                // it resumes only if the user was watching and auto-resume is on,
                // otherwise it asserts a pause to squash any WebKit self-resume.
                env.controller.enterForeground(autoResume: env.localStore.settings().autoResume)
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
