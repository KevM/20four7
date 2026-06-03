import SwiftUI

/// Unified edit form for an existing channel. Title, tags, live/VOD, and favorite
/// are editable; the YouTube link is fixed (it defines identity). Saving a curated
/// channel adopts it into a user copy via `ChannelStore.editChannel`.
struct EditChannelView: View {
    @ObservedObject var store: ChannelStore
    let channel: Channel
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var selectedTagIDs: Set<String>
    @State private var isLiveExpected: Bool
    @State private var isFavorite: Bool

    /// `initialTagIDs` and `initialIsFavorite` are computed by the presenter
    /// (which is already on the main actor) so this initializer stays pure.
    init(
        store: ChannelStore,
        channel: Channel,
        initialTagIDs: Set<String>,
        initialIsFavorite: Bool,
        onSaved: @escaping () -> Void
    ) {
        self.store = store
        self.channel = channel
        self.onSaved = onSaved
        self._title = State(initialValue: channel.title)
        self._selectedTagIDs = State(initialValue: initialTagIDs)
        self._isLiveExpected = State(initialValue: channel.isLiveExpected)
        self._isFavorite = State(initialValue: initialIsFavorite)
    }

    var body: some View {
        Form {
            Section("YouTube link") {
                Text("youtu.be/\(channel.youTubeVideoID)")
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Section("Title") {
                TextField("Channel name", text: $title)
            }
            TagSelectorSection(
                availableTags: store.selectableTags(including: selectedTagIDs),
                selectedTagIDs: $selectedTagIDs
            )
            Section("Status") {
                Toggle("Live", isOn: $isLiveExpected)
                Toggle("Favorite", isOn: $isFavorite)
            }
        }
        .navigationTitle("Edit Channel")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    store.editChannel(channel, title: title,
                                      tagIDs: Array(selectedTagIDs),
                                      isLiveExpected: isLiveExpected,
                                      isFavorite: isFavorite)
                    onSaved()
                    dismiss()
                }
            }
        }
    }
}
