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

    @State private var contentWidth: CGFloat = 0

    /// Number of channels to feature: two full rows at the featured size,
    /// capped at the number available. Zero on compact, or before the width
    /// has been measured (avoids featuring the wrong count on first frame).
    private var featuredCount: Int {
        guard contentWidth > 0 else { return 0 }
        return min(m.featuredChannelCount(availableWidth: contentWidth),
                   store.filteredChannels.count)
    }

    /// Explicit columns for the featured grid, so "rows" are deterministic.
    private var featuredColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: m.gridSpacing),
              count: m.featuredColumnCount(availableWidth: contentWidth))
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
                    if featuredCount > 0 {
                        let featured = Array(store.filteredChannels.prefix(featuredCount))
                        let rest = Array(store.filteredChannels.dropFirst(featuredCount))
                        LazyVGrid(columns: featuredColumns, spacing: m.gridSpacing) {
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
                // `.background` sits before `.padding` so it measures the
                // content width *inside* the horizontal padding — the width the
                // tiles actually occupy, which the column math expects.
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(key: GuideContentWidthKey.self,
                                               value: geo.size.width)
                    }
                )
                .padding(.horizontal, m.gridHPadding)
                .onPreferenceChange(GuideContentWidthKey.self) { width in
                    contentWidth = width
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

/// Publishes the Guide grid's content width (inside horizontal padding) so the
/// view can compute how many featured columns fit. Reduces by `max` so the
/// widest reported frame wins.
private struct GuideContentWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
