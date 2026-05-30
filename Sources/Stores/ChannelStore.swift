import Foundation
import Combine

/// Combines the remote curated catalog with local user channels and exposes the
/// merged, filterable lineup plus the tag dictionary for resolution/chips.
@MainActor
final class ChannelStore: ObservableObject {
    @Published private(set) var channels: [Channel] = []
    @Published private(set) var tagsByID: [String: Tag] = [:]
    @Published private(set) var editorialTags: [Tag] = []
    @Published private(set) var favoriteIDs: Set<String> = []
    @Published var selectedTagIDs: Set<String> = []

    private let remoteConfig: RemoteConfig
    private let localStore: LocalStore

    init(remoteConfig: RemoteConfig, localStore: LocalStore) {
        self.remoteConfig = remoteConfig
        self.localStore = localStore
    }

    var filteredChannels: [Channel] {
        TagFilter.filter(channels, anyOf: selectedTagIDs)
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// All chips shown in the Guide: editorial tags + the user's tags, de-duped.
    var chipTags: [Tag] { editorialTags }

    func refresh() async {
        let catalog = await remoteConfig.currentCatalog()
        let curated = catalog.asChannels()
        let user = localStore.userChannels()
        var dict: [String: Tag] = [:]
        for tag in catalog.editorialTags() { dict[tag.id] = tag }
        self.tagsByID = dict
        self.editorialTags = catalog.editorialTags()
        self.channels = ChannelMerger.merge(curated: curated, user: user)
        self.favoriteIDs = localStore.favoriteChannelIDs()
    }

    func resolveTags(_ channel: Channel) -> [Tag] {
        TagFilter.resolve(channel.tagIDs, in: tagsByID)
    }

    func toggleTag(_ id: String) {
        if selectedTagIDs.contains(id) { selectedTagIDs.remove(id) } else { selectedTagIDs.insert(id) }
    }

    func toggleFavorite(_ channel: Channel) {
        let now = !favoriteIDs.contains(channel.id)
        localStore.setFavorite(channelID: channel.id, isFavorite: now)
        favoriteIDs = localStore.favoriteChannelIDs()
    }

    func isFavorite(_ channel: Channel) -> Bool { favoriteIDs.contains(channel.id) }
}
