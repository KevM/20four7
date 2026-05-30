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
    @Published private(set) var chipTags: [Tag] = []

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

    func refresh() async {
        let catalog = await remoteConfig.currentCatalog()
        let curated = catalog.asChannels()
        let user = localStore.userChannels()
        
        var dict: [String: Tag] = [:]
        let editorial = catalog.editorialTags()
        for tag in editorial { dict[tag.id] = tag }
        
        var userTags: [Tag] = []
        for channel in user {
            for tagID in channel.tagIDs {
                if dict[tagID] == nil && !userTags.contains(where: { $0.id == tagID }) {
                    let userTag = Tag(id: tagID, name: tagID, symbol: nil, kind: .user, sortOrder: 100)
                    userTags.append(userTag)
                    dict[tagID] = userTag
                }
            }
        }
        
        self.tagsByID = dict
        self.editorialTags = editorial
        self.channels = ChannelMerger.merge(curated: curated, user: user)
        self.favoriteIDs = localStore.favoriteChannelIDs()
        
        let allTags = editorial + userTags
        self.chipTags = allTags.sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
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
