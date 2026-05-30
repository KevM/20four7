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
    @State private var isFetchingTitle = false
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
                        case .video:  Label("Valid video link", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        case .handle: Label("Handles aren't supported yet — paste a video/live link", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                        case nil:     Label("Not a recognizable YouTube link", systemImage: "xmark.circle").foregroundStyle(.red)
                        }
                    }
                }
                Section("Title") {
                    HStack {
                        TextField("Channel name", text: $title)
                        if isFetchingTitle {
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
                fetchTitleIfNeeded(for: newValue)
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

    private func fetchTitleIfNeeded(for rawText: String) {
        guard let ref = ChannelValidator.parseReference(rawText) else { return }
        if case .video(let id) = ref {
            isFetchingTitle = true
            Task {
                if let fetchedTitle = await fetchYouTubeTitle(videoID: id) {
                    if title.isEmpty {
                        title = fetchedTitle
                    }
                }
                isFetchingTitle = false
            }
        }
    }

    private func fetchYouTubeTitle(videoID: String) async -> String? {
        let urlString = "https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=\(videoID)&format=json"
        guard let url = URL(string: urlString) else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return nil }
            let oembed = try JSONDecoder().decode(YouTubeOEmbed.self, from: data)
            return oembed.title
        } catch {
            return nil
        }
    }

    private struct YouTubeOEmbed: Codable {
        let title: String
    }
}
