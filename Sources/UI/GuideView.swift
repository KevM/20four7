import SwiftUI

struct GuideView: View {
    @ObservedObject var store: ChannelStore
    let onSelect: (Channel) -> Void

    @State private var renameText = ""
    @State private var channelToRename: Channel? = nil
    @State private var showingRenameAlert = false

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 8)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                TagChipBar(tags: store.chipTags, selected: store.selectedTagIDs) { id in
                    if id == "__all__" { store.selectedTagIDs.removeAll() } else { store.toggleTag(id) }
                    store.startBackgroundScan()
                }
                LazyVGrid(columns: columns, spacing: 8) {
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
                .padding(.horizontal, 12)
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
