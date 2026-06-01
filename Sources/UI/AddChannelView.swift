import SwiftUI

struct AddChannelView: View {
    @ObservedObject var store: ChannelStore
    let localStore: LocalStore
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var urlText = ""
    @State private var title = ""
    @State private var selectedTagIDs: Set<String> = []
    @State private var newTagName = ""
    @State private var isCheckingVideo = false
    @State private var validationError: String? = nil
    @State private var isVideoEmbeddable: Bool? = nil
    @State private var error: String?

    private var reference: YouTubeReference? { ChannelValidator.parseReference(urlText) }

    private var allAvailableTags: [Tag] {
        var tags = store.editorialTags
        for tagID in selectedTagIDs {
            if !tags.contains(where: { $0.id == tagID }) {
                tags.append(Tag(id: tagID, name: tagID, symbol: nil, kind: .user, sortOrder: 100))
            }
        }
        for tag in store.chipTags {
            if tag.kind == .user && !tags.contains(where: { $0.id == tag.id }) {
                tags.append(tag)
            }
        }
        return tags.sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("YouTube link") {
                    TextField("https://youtube.com/watch?v=… or youtu.be/…", text: $urlText)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    if !urlText.isEmpty {
                        switch reference {
                        case .video:
                            if isCheckingVideo {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Checking video embeddability...")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            } else if let validationError {
                                Label(validationError, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                            } else {
                                Label("Valid video link (embeddable)", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                            }
                        case .handle: Label("Handles aren't supported yet — paste a video/live link", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                        case nil:     Label("Not a recognizable YouTube link", systemImage: "xmark.circle").foregroundStyle(.red)
                        }
                    }
                }
                Section("Title") {
                    HStack {
                        TextField("Channel name", text: $title)
                        if isCheckingVideo {
                            ProgressView()
                                .padding(.leading, 8)
                        }
                    }
                }
                Section("Tags") {
                    ForEach(allAvailableTags) { tag in
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
                Section("Add Custom Tag") {
                    HStack {
                        TextField("New tag name (e.g. Nature)", text: $newTagName)
                            .autocorrectionDisabled()
                        Button("Create") {
                            let trimmed = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty {
                                selectedTagIDs.insert(trimmed)
                                newTagName = ""
                            }
                        }
                        .disabled(newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Add Channel")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Add") { save() }.disabled(!canSave) }
            }
            .onChange(of: urlText) { _, newValue in
                validationError = nil
                isVideoEmbeddable = nil
                fetchTitleAndValidateIfNeeded(for: newValue)
            }
        }
    }

    private var canSave: Bool {
        if case .video = reference {
            return isVideoEmbeddable != false && !isCheckingVideo
        }
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

    private func fetchTitleAndValidateIfNeeded(for rawText: String) {
        guard let ref = ChannelValidator.parseReference(rawText) else {
            isVideoEmbeddable = nil
            validationError = nil
            isCheckingVideo = false
            return
        }
        if case .video(let id) = ref {
            isCheckingVideo = true
            Task {
                let result = await ChannelValidator.validateVideoEmbeddability(videoID: id)
                guard urlText == rawText else { return }

                switch result {
                case .success(let fetchedTitle):
                    isVideoEmbeddable = true
                    validationError = nil
                    if title.isEmpty {
                        title = fetchedTitle
                    }
                case .failure(let err):
                    if case .networkError = err {
                        isVideoEmbeddable = nil
                    } else {
                        isVideoEmbeddable = false
                    }
                    validationError = err.localizedDescription
                }
                isCheckingVideo = false
            }
        } else {
            isVideoEmbeddable = nil
            validationError = nil
            isCheckingVideo = false
        }
    }
}
