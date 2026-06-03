import SwiftUI

struct AddChannelView: View {
    @ObservedObject var store: ChannelStore
    let localStore: LocalStore
    let initialURLText: String
    let initialTitle: String
    let startTime: Double
    let onSaved: () -> Void
    let onWatchNow: (Channel, Double) -> Void
    let onSearchMore: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var urlText: String
    @State private var title: String
    @State private var selectedTagIDs: Set<String> = []
    @State private var isCheckingVideo = false
    @State private var validationError: String? = nil

    @State private var isVideoEmbeddable: Bool? = nil
    @State private var error: String?

    @State private var showWatchAlert = false
    @State private var addedChannel: Channel? = nil

    init(
        store: ChannelStore,
        localStore: LocalStore,
        initialURLText: String = "",
        initialTitle: String = "",
        startTime: Double = 0.0,
        onSaved: @escaping () -> Void,
        onWatchNow: @escaping (Channel, Double) -> Void,
        onSearchMore: @escaping () -> Void
    ) {
        self.store = store
        self.localStore = localStore
        self.initialURLText = initialURLText
        self.initialTitle = initialTitle
        self.startTime = startTime
        self.onSaved = onSaved
        self.onWatchNow = onWatchNow
        self.onSearchMore = onSearchMore
        
        self._urlText = State(initialValue: initialURLText)
        self._title = State(initialValue: initialTitle)
    }

    private var reference: YouTubeReference? { ChannelValidator.parseReference(urlText) }




    var body: some View {
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
            TagSelectorSection(
                availableTags: store.selectableTags(including: selectedTagIDs),
                selectedTagIDs: $selectedTagIDs
            )
            if let error { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle("Add Channel")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                    save()
                }
                .disabled(!canSave)
            }
        }
        .onChange(of: urlText) { _, newValue in
            validationError = nil
            isVideoEmbeddable = nil
            fetchTitleAndValidateIfNeeded(for: newValue)
        }
        .onAppear {
            if !urlText.isEmpty {
                fetchTitleAndValidateIfNeeded(for: urlText)
            }
        }
        .alert("Channel Added!", isPresented: $showWatchAlert, presenting: addedChannel) { channel in
            Button("Watch Now") {
                onWatchNow(channel, startTime)
            }
            Button("Search More", role: .cancel) {
                onSearchMore()
                dismiss()
            }
        } message: { channel in
            Text("Would you like to start watching \"\(channel.title)\" now in the player, or go back to find more streams?")
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
        
        self.addedChannel = channel
        self.showWatchAlert = true
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
