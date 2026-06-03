import SwiftUI

struct GuideView: View {
    @ObservedObject var store: ChannelStore
    let onSelect: (Channel) -> Void

    @State private var channelToEdit: Channel? = nil

    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var m: LayoutMetrics { LayoutMetrics(hSizeClass) }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: m.tileMinWidth), spacing: m.gridSpacing)]
    }

    private var hasChips: Bool { !store.selectedTagIDs.isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // While filtering: active-filter chips (tap to remove). These sit
                // just under the system "Guide" title and scroll away with the
                // content as the title collapses into the nav bar. The Filter
                // entry point and Auto-Surf both live in the toolbar (RootView).
                if hasChips {
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
