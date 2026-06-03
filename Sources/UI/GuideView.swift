import SwiftUI

struct GuideView: View {
    @ObservedObject var store: ChannelStore
    let onSelect: (Channel) -> Void
    let onAutoSurf: () -> Void

    @State private var channelToEdit: Channel? = nil

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
                            onEdit: {
                                channelToEdit = channel
                            },
                            onRemove: { store.removeChannel(channel) }
                        )
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
        }
        .refreshable {
            await store.refresh()
        }
        .sheet(item: $channelToEdit) { channel in
            NavigationStack {
                EditChannelView(
                    store: store,
                    channel: channel,
                    initialTagIDs: Set(store.resolveTags(channel).map(\.id)),
                    initialIsFavorite: store.isFavorite(channel),
                    onSaved: {}
                )
            }
        }
    }
}
