import SwiftUI

struct AddChannelView: View {
    @ObservedObject var store: ChannelStore
    let localStore: LocalStore
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var urlText = ""
    @State private var title = ""
    @State private var selectedTagIDs: Set<String> = []
    @State private var error: String?

    private var reference: YouTubeReference? { ChannelValidator.parseReference(urlText) }

    var body: some View {
        NavigationStack {
            Form {
                Section("YouTube link") {
                    TextField("https://youtube.com/watch?v=… or youtu.be/…", text: $urlText)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    if !urlText.isEmpty {
                        switch reference {
                        case .video:  Label("Valid video link", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        case .handle: Label("Handles aren't supported yet — paste a video/live link", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                        case nil:     Label("Not a recognizable YouTube link", systemImage: "xmark.circle").foregroundStyle(.red)
                        }
                    }
                }
                Section("Title") { TextField("Channel name", text: $title) }
                Section("Tags") {
                    ForEach(store.editorialTags) { tag in
                        Button {
                            if selectedTagIDs.contains(tag.id) { selectedTagIDs.remove(tag.id) }
                            else { selectedTagIDs.insert(tag.id) }
                        } label: {
                            HStack {
                                Text(tag.name)
                                Spacer()
                                if selectedTagIDs.contains(tag.id) { Image(systemName: "checkmark") }
                            }
                        }
                    }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Add Channel")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Add") { save() }.disabled(!canSave) }
            }
        }
    }

    private var canSave: Bool {
        if case .video = reference { return true }
        return false
    }

    private func save() {
        guard let reference,
              let channel = ChannelValidator.makeUserChannel(
                from: reference, title: title, tagIDs: Array(selectedTagIDs), now: Date()) else {
            error = "Couldn't build a channel from that link."
            return
        }
        localStore.addUserChannel(channel)
        onSaved()
        dismiss()
    }
}
