import Foundation
import Combine
import WebKit

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
    @Published private(set) var showOffline: Bool = false
    /// Channels detected as offline during the current app session.
    /// Note: This is intentionally kept in-memory only (resets on launch) to avoid
    /// permanently hiding transiently offline feeds, whereas live-status overrides
    /// (VOD vs Live) represent structural channel properties and are persisted.
    @Published private(set) var offlineChannelIDs: Set<String> = []
    @Published private(set) var visibleChannelIDs: Set<String> = []
    @Published private(set) var tagTapCounts: [String: Int] = [:]
    @Published private(set) var tagChannelCounts: [String: Int] = [:]

    private let remoteConfig: RemoteConfig
    private let localStore: LocalStore
    private var scanner: BackgroundLineupScanner?

    init(remoteConfig: RemoteConfig, localStore: LocalStore) {
        self.remoteConfig = remoteConfig
        self.localStore = localStore
        setupInitialLineup()
        self.scanner = BackgroundLineupScanner(store: self)
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
        self.chipTags = allTags.sorted { a, b in
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
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }
    var filteredChannels: [Channel] {
        let list = showOffline ? channels : channels.filter { !offlineChannelIDs.contains($0.id) }
        return TagFilter.filter(list, anyOf: selectedTagIDs)
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    var filteredPlaylistURL: URL? {
        let videoIDs = filteredChannels.map { $0.youTubeVideoID }
        guard !videoIDs.isEmpty else { return nil }
        return URL(string: "https://www.youtube.com/watch_videos?video_ids=\(videoIDs.joined(separator: ","))")
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
        reloadLineup()
    }

    func toggleFavorite(_ channel: Channel) {
        let now = !favoriteIDs.contains(channel.id)
        localStore.setFavorite(channelID: channel.id, isFavorite: now)
        favoriteIDs = localStore.favoriteChannelIDs()
    }

    func isFavorite(_ channel: Channel) -> Bool { favoriteIDs.contains(channel.id) }

    func markChannelOffline(id: String) {
        offlineChannelIDs.insert(id)
    }

    func updateLiveStatus(channelID: String, isLive: Bool) {
        guard let idx = channels.firstIndex(where: { $0.id == channelID }) else { return }
        let currentChannel = channels[idx]
        
        if currentChannel.isLiveExpected != isLive {
            localStore.setLiveExpectedOverride(channelID: channelID, isLive: isLive)
            
            var updatedChannels = channels
            updatedChannels[idx].isLiveExpected = isLive
            self.channels = updatedChannels
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
    }

    func startBackgroundScan(force: Bool = false) {
        scanner?.startScanIfNeeded(localStore: localStore, force: force)
    }

    func stopBackgroundScan() {
        scanner?.stopScan()
    }

    var hasRemovedChannels: Bool {
        localStore.hasAnyHiddenChannels()
    }

    var scannerWebView: WKWebView? {
        scanner?.webView
    }

    func markChannelVisible(_ id: String) {
        visibleChannelIDs.insert(id)
    }

    func markChannelInvisible(_ id: String) {
        visibleChannelIDs.remove(id)
    }
}
