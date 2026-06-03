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
    @Published var selectedTagIDs: Set<String> = [] {
        didSet {
            resortChipTags()
            recomputeFilteredChannels()
        }
    }
    @Published private(set) var chipTags: [Tag] = []
    @Published private(set) var showOffline: Bool = false
    /// Channels detected as offline during the current app session.
    /// Note: This is intentionally kept in-memory only (resets on launch) to avoid
    /// permanently hiding transiently offline feeds, whereas live-status overrides
    /// (VOD vs Live) represent structural channel properties and are persisted.
    @Published private(set) var offlineChannelIDs: Set<String> = []
    @Published private(set) var tagTapCounts: [String: Int] = [:]
    @Published private(set) var tagChannelCounts: [String: Int] = [:]
    @Published private(set) var filteredChannels: [Channel] = []
    @Published private(set) var filteredPlaylistURL: URL? = nil

    private let remoteConfig: RemoteConfig
    private let localStore: LocalStore

    init(remoteConfig: RemoteConfig, localStore: LocalStore) {
        self.remoteConfig = remoteConfig
        self.localStore = localStore
        setupInitialLineup()
    }

    private func setupInitialLineup() {
        self.offlineChannelIDs = []
        self.tagTapCounts = localStore.tagTapCounts()
        reloadLineup()
    }

    func reloadLineup() {
        let catalog = remoteConfig.cachedOrBundledCatalog()
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
        self.showOffline = localStore.settings().showOffline
        let userStates = localStore.allUserStates()
        self.channels = ChannelMerger.merge(curated: curated, user: user, userStates: userStates)
        self.favoriteIDs = localStore.favoriteChannelIDs()
        
        var counts: [String: Int] = [:]
        for channel in channels {
            for tagID in channel.tagIDs {
                counts[tagID, default: 0] += 1
            }
        }
        self.tagChannelCounts = counts

        let allTags = editorial + userTags
        self.chipTags = allTags
        resortChipTags()
        recomputeFilteredChannels()
    }

    private func recomputeFilteredChannels() {
        let list = showOffline ? channels : channels.filter { !offlineChannelIDs.contains($0.id) }
        let now = Date()
        let filtered = TagFilter.filter(list, anyOf: selectedTagIDs)
            .sorted { a, b in
                let scoreA = popularityScore(for: a, now: now)
                let scoreB = popularityScore(for: b, now: now)
                let roundedA = (scoreA * 1000.0).rounded()
                let roundedB = (scoreB * 1000.0).rounded()
                if roundedA != roundedB {
                    return roundedA > roundedB
                }
                return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            }
        
        self.filteredChannels = filtered
        
        let videoIDs = filtered.map { $0.youTubeVideoID }
        if videoIDs.isEmpty {
            self.filteredPlaylistURL = nil
        } else {
            self.filteredPlaylistURL = URL(string: "https://www.youtube.com/watch_videos?video_ids=\(videoIDs.joined(separator: ","))")
        }
    }

    private func isBaseSortBefore(_ a: Tag, _ b: Tag) -> Bool {
        let aTaps = tagTapCounts[a.id, default: 0]
        let bTaps = tagTapCounts[b.id, default: 0]
        if aTaps != bTaps {
            return aTaps > bTaps
        }
        let aCount = tagChannelCounts[a.id, default: 0]
        let bCount = tagChannelCounts[b.id, default: 0]
        if aCount != bCount {
            return aCount > bCount
        }
        if a.sortOrder != b.sortOrder {
            return a.sortOrder < b.sortOrder
        }
        return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
    }

    private func resortChipTags() {
        self.chipTags.sort { a, b in
            let aSelected = selectedTagIDs.contains(a.id)
            let bSelected = selectedTagIDs.contains(b.id)
            if aSelected != bSelected {
                return aSelected
            }
            return isBaseSortBefore(a, b)
        }
    }

    private func popularityScore(for channel: Channel, now: Date) -> Double {
        let playCount = Double(channel.playCount)
        
        // Recency boost: up to 10 points decaying linearly over 7 days (604,800 seconds)
        // Decays from the last played date if available, otherwise dateAdded.
        let referenceDate = channel.lastPlayedDate ?? channel.dateAdded
        let age = now.timeIntervalSince(referenceDate)
        let recencyBoost: Double
        if age >= 0 && age < 604800 {
            recencyBoost = 10.0 * (1.0 - age / 604800.0)
        } else {
            recencyBoost = 0.0
        }
        
        return playCount + recencyBoost
    }

    func refresh() async {
        _ = await remoteConfig.currentCatalog()
        reloadLineup()
    }

    func resolveTags(_ channel: Channel) -> [Tag] {
        TagFilter.resolve(channel.tagIDs, in: tagsByID)
    }

    func toggleTag(_ id: String) {
        if selectedTagIDs.contains(id) {
            selectedTagIDs.remove(id)
        } else {
            selectedTagIDs.insert(id)
            tagTapCounts[id, default: 0] += 1
            Task {
                localStore.incrementTagTapCount(tagID: id)
            }
        }
    }

    func toggleFavorite(_ channel: Channel) {
        let now = !favoriteIDs.contains(channel.id)
        localStore.setFavorite(channelID: channel.id, isFavorite: now)
        favoriteIDs = localStore.favoriteChannelIDs()
    }

    func isFavorite(_ channel: Channel) -> Bool { favoriteIDs.contains(channel.id) }

    func markChannelOffline(id: String) {
        offlineChannelIDs.insert(id)
        recomputeFilteredChannels()
    }

    func updateLiveStatus(channelID: String, isLive: Bool) {
        guard let idx = channels.firstIndex(where: { $0.id == channelID }) else { return }
        let currentChannel = channels[idx]
        
        if currentChannel.isLiveExpected != isLive {
            localStore.setLiveExpectedOverride(channelID: channelID, isLive: isLive)
            
            var updatedChannels = channels
            updatedChannels[idx].isLiveExpected = isLive
            self.channels = updatedChannels
            recomputeFilteredChannels()
        }
    }

    func toggleLiveExpected(for channel: Channel) {
        let newLive = !channel.isLiveExpected
        localStore.setLiveExpectedOverride(channelID: channel.id, isLive: newLive)
        reloadLineup()
    }

    func removeChannel(_ channel: Channel) {
        if channel.source == .user {
            localStore.removeUserChannel(id: channel.id)
        } else {
            localStore.setHidden(channelID: channel.id, isHidden: true)
        }
        
        if favoriteIDs.contains(channel.id) {
            localStore.setFavorite(channelID: channel.id, isFavorite: false)
            favoriteIDs.remove(channel.id)
        }
        
        reloadLineup()
    }

    func renameChannel(_ channel: Channel, to newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        if channel.source == .user {
            localStore.updateUserChannelTitle(id: channel.id, title: trimmed)
        } else {
            localStore.setCustomTitle(channelID: channel.id, title: trimmed)
        }
        
        reloadLineup()
    }

    func restoreRemovedChannels() {
        localStore.restoreAllHiddenChannels()
        reloadLineup()
    }

    func markChannelOnline(id: String) {
        offlineChannelIDs.remove(id)
        recomputeFilteredChannels()
    }
    
    func bumpPlayCount(channelID: String, playCount: Int, lastPlayedDate: Date) {
        if let idx = channels.firstIndex(where: { $0.id == channelID }) {
            channels[idx].playCount = playCount
            channels[idx].lastPlayedDate = lastPlayedDate
            recomputeFilteredChannels()
        }
    }

    var hasRemovedChannels: Bool {
        localStore.hasAnyHiddenChannels()
    }
}
