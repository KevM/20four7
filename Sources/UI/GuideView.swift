import SwiftUI

struct GuideView: View {
    @ObservedObject var store: ChannelStore
    let onSelect: (Channel) -> Void
    let onSearchYouTube: (String) -> Void

    @State private var channelToEdit: Channel? = nil

    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var m: LayoutMetrics { LayoutMetrics(hSizeClass) }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: m.tileMinWidth), spacing: m.gridSpacing)]
    }

    private var hasChips: Bool { !store.selectedTagIDs.isEmpty }

    private var trimmedQuery: String {
        store.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearching: Bool {
        !trimmedQuery.isEmpty
    }

    /// Number of channels to feature: two full rows at the featured size,
    /// capped at the number available. Zero on compact (where `featuredRowCount`
    /// is 0) or before the enclosing `GeometryReader` has a width.
    private func featuredCount(_ availableWidth: CGFloat) -> Int {
        guard availableWidth > 0, !isSearching else { return 0 }
        return min(m.featuredChannelCount(availableWidth: availableWidth),
                   store.filteredChannels.count)
    }

    /// Explicit columns for the featured grid, so "rows" are deterministic.
    private func featuredColumns(_ availableWidth: CGFloat) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: m.gridSpacing),
              count: m.featuredColumnCount(availableWidth: availableWidth))
    }

    @ViewBuilder
    private func tile(for channel: Channel, isFeatured: Bool) -> some View {
        ChannelTile(
            channel: channel,
            isFeatured: isFeatured,
            isFavorite: store.isFavorite(channel),
            isOffline: store.offlineChannelIDs.contains(channel.id),
            onTap: { onSelect(channel) },
            onToggleFavorite: { store.toggleFavorite(channel) },
            onEdit: { channelToEdit = channel },
            onRemove: { store.removeChannel(channel) }
        )
    }

    var body: some View {
        // A single top-level GeometryReader hands us the content width *during*
        // layout, so the featured split is correct on the first frame — no
        // measure-then-reflow. Greedy fill is exactly right here: GuideView is
        // full-screen, and the ScrollView fills it and scrolls as usual.
        GeometryReader { proxy in
            let availableWidth = max(0, proxy.size.width - 2 * m.gridHPadding)
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

                    Group {
                        let count = featuredCount(availableWidth)
                        if count > 0 {
                            let featured = Array(store.filteredChannels.prefix(count))
                            let rest = Array(store.filteredChannels.dropFirst(count))
                            LazyVGrid(columns: featuredColumns(availableWidth), spacing: m.gridSpacing) {
                                ForEach(featured) { tile(for: $0, isFeatured: true) }
                            }
                            if !rest.isEmpty {
                                LazyVGrid(columns: columns, spacing: m.gridSpacing) {
                                    ForEach(rest) { tile(for: $0, isFeatured: false) }
                                }
                            }
                        } else {
                            LazyVGrid(columns: columns, spacing: m.gridSpacing) {
                                ForEach(store.filteredChannels) { tile(for: $0, isFeatured: false) }
                            }
                        }
                    }
                    .padding(.horizontal, m.gridHPadding)

                    if isSearching {
                        VStack(spacing: 16) {
                            if store.filteredChannels.isEmpty {
                                Text("No channels in your Guide match \"\(trimmedQuery)\".")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 24)
                            }

                            Button {
                                onSearchYouTube(trimmedQuery)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "magnifyingglass.badge.plus")
                                    Text("Search YouTube")
                                }
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding()
                                .frame(width: m.searchYouTubeButtonWidth(availableWidth: availableWidth))
                                .background(Color.brandAccent)
                                .cornerRadius(10)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, m.searchFooterTopSpacing)
                        .padding(.bottom, 24)
                    }
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
}
