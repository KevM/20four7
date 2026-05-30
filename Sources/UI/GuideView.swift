import SwiftUI

struct GuideView: View {
    @ObservedObject var store: ChannelStore
    let onSelect: (Channel) -> Void

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 8)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                TagChipBar(tags: store.chipTags, selected: store.selectedTagIDs) { id in
                    if id == "__all__" { store.selectedTagIDs.removeAll() } else { store.toggleTag(id) }
                }
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(store.filteredChannels) { channel in
                        ChannelTile(channel: channel, isFavorite: store.isFavorite(channel)) {
                            onSelect(channel)
                        }
                    }
                }
                .padding(.horizontal, 12)
            }
            .padding(.top, 8)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Guide")
        .task { await store.refresh() }
        .refreshable { await store.refresh() }
    }
}
