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
            if isRestored { localStore.saveSelectedFilterTagIDs(Array(selectedTagIDs)) }
        }
    }
    /// Gates persistence until the initial selection has been restored, so the
    /// empty default doesn't overwrite the saved filter before it's loaded.
    private var isRestored = false
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
        // Restore the previously active filter, dropping any tags that no longer
        // exist (e.g. a user tag whose only channel was removed). The favs tag is
        // only present in tagsByID when at least one favorite remains.
        let restored = localStore.selectedFilterTagIDs().filter { tagsByID[$0] != nil }
        selectedTagIDs = Set(restored)
        isRestored = true
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

        var allTags = editorial + userTags
        if (counts[Tag.favsID] ?? 0) > 0 {
            allTags.insert(Tag.favs, at: 0)
            dict[Tag.favsID] = Tag.favs
        }
        self.tagsByID = dict
        self.chipTags = allTags
        
        // If the last favorite was removed, drop favs from the active selection so the
        // guide does not get stuck on a now-hidden, empty filter.
        if (counts[Tag.favsID] ?? 0) == 0, selectedTagIDs.contains(Tag.favsID) {
            selectedTagIDs.remove(Tag.favsID)
        }
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
        let aFavs = a.id == Tag.favsID
        let bFavs = b.id == Tag.favsID
        if aFavs != bFavs { return aFavs }
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
        TagFilter.resolve(channel.tagIDs, in: tagsByID).filter { $0.kind != .derived }
    }

    /// Tags offered in the add/edit forms: editorial tags, plus any currently
    /// selected ids not already present (materialized as `.user` tags), plus existing
    /// user chip tags. Sorted by (sortOrder, name). Excludes the derived favs tag.
    func selectableTags(including extraIDs: Set<String>) -> [Tag] {
        var tags = editorialTags
        for tagID in extraIDs where tagID != Tag.favsID {
            if !tags.contains(where: { $0.id == tagID }) {
                tags.append(Tag(id: tagID, name: tagID, symbol: nil, kind: .user, sortOrder: 100))
            }
        }
        for tag in chipTags where tag.kind == .user {
            if !tags.contains(where: { $0.id == tag.id }) {
                tags.append(tag)
            }
        }
        return tags.sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
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
        // Re-derive so the injected favs ids, chip presence/count, pinning, and the
        // filtered lineup all update. reloadLineup refreshes favoriteIDs from the store.
        reloadLineup()
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

    func removeChannel(_ channel: Channel) {
        if channel.source == .user {
            localStore.removeUserChannel(id: channel.id)
            // Hide a curated twin sharing this video id, so an adopted-then-removed
            // channel does not silently reappear from the catalog.
            let catalog = remoteConfig.cachedOrBundledCatalog()
            if let twin = catalog.asChannels().first(where: { $0.youTubeVideoID == channel.youTubeVideoID }) {
                localStore.setHidden(channelID: twin.id, isHidden: true)
            }
        } else {
            localStore.setHidden(channelID: channel.id, isHidden: true)
        }

        if favoriteIDs.contains(channel.id) {
            localStore.setFavorite(channelID: channel.id, isFavorite: false)
            favoriteIDs.remove(channel.id)
        }

        reloadLineup()
    }

    /// Unified channel edit. User channels are updated in place; curated channels are
    /// adopted into a user copy (the merge's video-id dedup hides the curated original).
    /// Favorite is applied to whichever id is now authoritative.
    func editChannel(_ original: Channel, title: String, tagIDs: [String],
                     isLiveExpected: Bool, isFavorite: Bool) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = trimmed.isEmpty ? "Untitled" : trimmed
        let cleanTags = tagIDs.filter { $0 != Tag.favsID }

        switch original.source {
        case .user:
            localStore.updateUserChannel(id: original.id, title: finalTitle,
                                         youTubeVideoID: original.youTubeVideoID,
                                         isLiveExpected: isLiveExpected, tagIDs: cleanTags)
            localStore.setFavorite(channelID: original.id, isFavorite: isFavorite)
        case .curated:
            let adopted = Channel(
                id: "user-\(original.youTubeVideoID)", title: finalTitle,
                youTubeVideoID: original.youTubeVideoID, thumbnailURL: original.thumbnailURL,
                source: .user, isLiveExpected: isLiveExpected,
                dateAdded: original.dateAdded, tagIDs: cleanTags)
            localStore.adoptCuratedChannel(adopted, fromCuratedID: original.id)
            localStore.setFavorite(channelID: adopted.id, isFavorite: isFavorite)
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
