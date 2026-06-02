import SwiftUI

struct GuideView: View {
    @ObservedObject var store: ChannelStore
    let onSelect: (Channel) -> Void
    let onAutoSurf: () -> Void

    @State private var renameText = ""
    @State private var channelToRename: Channel? = nil
    @State private var showingRenameAlert = false
    @State private var showingTagPicker = false

    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var m: LayoutMetrics { LayoutMetrics(hSizeClass) }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: m.tileMinWidth), spacing: m.gridSpacing)]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                TagChipBar(
                    tags: store.chipTags,
                    selected: store.selectedTagIDs,
                    counts: store.tagChannelCounts,
                    onToggle: { id in
                        withAnimation {
                            store.toggleTag(id)
                        }
                        store.startBackgroundScan()
                    },
                    onEditFilters: {
                        showingTagPicker = true
                    }
                )
                
                if !store.selectedTagIDs.isEmpty && !store.filteredChannels.isEmpty {
                    let tagNames = store.selectedTagIDs
                        .compactMap { store.tagsByID[$0]?.name }
                        .sorted()
                        .joined(separator: ", ")
                    let formattedTagNames = "\(tagNames) Active"
                    
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(formattedTagNames)
                                .font(.subheadline.bold())
                                .foregroundColor(.white)
                            Text("\(store.filteredChannels.count) channels")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        
                        Spacer()
                        
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
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(12)
                    .padding(.horizontal, 12)
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
        .sheet(isPresented: $showingTagPicker) {
            TagPickerSheetView(store: store)
                .presentationDetents(m.wide ? [.large] : [.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}
