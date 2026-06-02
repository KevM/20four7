import SwiftUI

struct GuideView: View {
    @ObservedObject var store: ChannelStore
    let onSelect: (Channel) -> Void
    let onAutoSurf: () -> Void

    @State private var renameText = ""
    @State private var channelToRename: Channel? = nil
    @State private var showingRenameAlert = false

    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var m: LayoutMetrics { LayoutMetrics(hSizeClass) }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: m.tileMinWidth), spacing: m.gridSpacing)]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // While filtering: active-filter chips on the left (tap to remove),
                // Auto-Surf pinned on the right. The Filter entry point itself lives
                // in the toolbar (RootView).
                if !store.selectedTagIDs.isEmpty {
                    HStack(spacing: 8) {
                        TagChipBar(
                            tags: store.chipTags,
                            selected: store.selectedTagIDs,
                            counts: store.tagChannelCounts,
                            onToggle: { id in
                                withAnimation {
                                    store.toggleTag(id)
                                }
                                store.startBackgroundScan()
                            }
                        )

                        if !store.filteredChannels.isEmpty {
                            Button(action: onAutoSurf) {
                                HStack(spacing: 6) {
                                    Image(systemName: "play.circle.fill")
                                        .font(.body)
                                    Text("Auto-Surf")
                                        .font(.subheadline.bold())
                                }
                                .foregroundColor(.white)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 16)
                                .background(Color.red)
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, m.chipRowHPadding)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                LazyVGrid(columns: columns, spacing: m.gridSpacing) {
                    ForEach(store.filteredChannels) { channel in
                        ChannelTile(
                            channel: channel,
                            isFavorite: store.isFavorite(channel),
                            isOffline: store.offlineChannelIDs.contains(channel.id),
                            onTap: { onSelect(channel) },
                            onToggleFavorite: { store.toggleFavorite(channel) },
                            onRename: {
                                renameText = channel.title
                                channelToRename = channel
                                showingRenameAlert = true
                            },
                            onToggleLive: { store.toggleLiveExpected(for: channel) },
                            onRemove: { store.removeChannel(channel) }
                        )
                        .onAppear { store.markChannelVisible(channel.id) }
                        .onDisappear { store.markChannelInvisible(channel.id) }
                    }
                }
                .padding(.horizontal, m.gridHPadding)
            }
            .padding(.top, 8)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Guide")
        .task {
            await store.refresh()
            store.startBackgroundScan()
        }
        .refreshable {
            await store.refresh()
            store.startBackgroundScan(force: true)
        }
        .alert("Rename Channel", isPresented: $showingRenameAlert) {
            TextField("New Title", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                if let channel = channelToRename {
                    store.renameChannel(channel, to: renameText)
                }
            }
        } message: {
            Text("Enter a new title for this channel.")
        }
    }
}
