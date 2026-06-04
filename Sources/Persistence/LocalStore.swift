import Foundation
import SwiftData

/// A plain value mirror of `AppSettingsRecord` used by the UI.
struct AppSettings: Equatable {
    var autoResume: Bool
    var defaultSleepMinutes: Int
    var showClockOverlay: Bool
    var dimLevelRaw: Int
    var showOffline: Bool
    var defaultAutoSurfMinutes: Int
}

/// A snapshot of what the user was last doing, used to restore a session.
struct ResumeState: Equatable {
    var channelID: String?
    var isAutoSurf: Bool
    var wasPlaying: Bool
}

/// CRUD facade over SwiftData. The single owner of the `ModelContext`.
@MainActor
final class LocalStore {
    private let context: ModelContext
    /// Retain the owning container. A `ModelContext` does not keep its
    /// `ModelContainer` alive; if the container deallocates, the context is
    /// orphaned and every operation traps inside SwiftData.
    private let container: ModelContainer
    init(context: ModelContext) {
        self.context = context
        self.container = context.container
    }

    // MARK: User channels
    func addUserChannel(_ channel: Channel) {
        let record = UserChannel(
            id: channel.id, title: channel.title, youTubeVideoID: channel.youTubeVideoID,
            thumbnailURLString: channel.thumbnailURL?.absoluteString,
            isLiveExpected: channel.isLiveExpected, dateAdded: channel.dateAdded,
            tagIDs: channel.tagIDs, userID: nil)
        context.insert(record)
        try? context.save()
    }

    func removeUserChannel(id: String) {
        let descriptor = FetchDescriptor<UserChannel>(predicate: #Predicate { $0.id == id })
        for record in (try? context.fetch(descriptor)) ?? [] { context.delete(record) }
        try? context.save()
    }

    func userChannels() -> [Channel] {
        let descriptor = FetchDescriptor<UserChannel>(sortBy: [SortDescriptor(\.dateAdded)])
        let records = (try? context.fetch(descriptor)) ?? []
        return records.map { r in
            Channel(id: r.id, title: r.title, youTubeVideoID: r.youTubeVideoID,
                    thumbnailURL: r.thumbnailURLString.flatMap(URL.init(string:)),
                    source: .user, isLiveExpected: r.isLiveExpected,
                    dateAdded: r.dateAdded, tagIDs: r.tagIDs)
        }
    }

    // MARK: Favorites / per-channel state
    private func userState(for channelID: String) -> ChannelUserState? {
        let descriptor = FetchDescriptor<ChannelUserState>(predicate: #Predicate { $0.channelID == channelID })
        return try? context.fetch(descriptor).first
    }

    @discardableResult
    func incrementPlayCount(channelID: String) -> (playCount: Int, lastPlayedDate: Date) {
        let date = Date()
        let count: Int
        if let existing = userState(for: channelID) {
            let next = (existing.playCount ?? 0) + 1
            existing.playCount = next
            existing.lastPlayedDate = date
            count = next
        } else {
            let state = ChannelUserState(channelID: channelID, playCount: 1, lastPlayedDate: date)
            context.insert(state)
            count = 1
        }
        try? context.save()
        return (count, date)
    }

    func setLastPlayedDate(channelID: String, date: Date) {
        if let existing = userState(for: channelID) {
            existing.lastPlayedDate = date
            try? context.save()
        }
    }

    /// Accumulate watch time for a channel and refresh its lastPlayedDate so the
    /// recency term stays fresh during long sessions. Returns the new running total.
    @discardableResult
    func recordWatch(channelID: String, seconds: TimeInterval, date: Date = Date()) -> (watchSeconds: Double, lastPlayedDate: Date) {
        let total: Double
        if let existing = userState(for: channelID) {
            let next = (existing.watchSeconds ?? 0) + seconds
            existing.watchSeconds = next
            existing.lastPlayedDate = date
            total = next
        } else {
            let state = ChannelUserState(channelID: channelID, lastPlayedDate: date, watchSeconds: seconds)
            context.insert(state)
            total = seconds
        }
        do {
            try context.save()
        } catch {
            print("[LocalStore] Failed to save watch time for \(channelID): \(error)")
        }
        return (total, date)
    }

    func setFavorite(channelID: String, isFavorite: Bool) {
        if let existing = userState(for: channelID) {
            existing.isFavorite = isFavorite
        } else {
            context.insert(ChannelUserState(channelID: channelID, isFavorite: isFavorite))
        }
        try? context.save()
    }

    func isFavorite(channelID: String) -> Bool { userState(for: channelID)?.isFavorite ?? false }

    func favoriteChannelIDs() -> Set<String> {
        let descriptor = FetchDescriptor<ChannelUserState>(predicate: #Predicate { $0.isFavorite == true })
        let records = (try? context.fetch(descriptor)) ?? []
        return Set(records.map(\.channelID))
    }

    func setLiveExpectedOverride(channelID: String, isLive: Bool?) {
        if let existing = userState(for: channelID) {
            existing.isLiveExpectedOverride = isLive
        } else {
            let state = ChannelUserState(channelID: channelID)
            state.isLiveExpectedOverride = isLive
            context.insert(state)
        }
        try? context.save()
    }

    func setHidden(channelID: String, isHidden: Bool) {
        if let existing = userState(for: channelID) {
            existing.isHidden = isHidden
        } else {
            let state = ChannelUserState(channelID: channelID)
            state.isHidden = isHidden
            context.insert(state)
        }
        try? context.save()
    }

    func restoreAllHiddenChannels() {
        let descriptor = FetchDescriptor<ChannelUserState>()
        if let records = try? context.fetch(descriptor) {
            for record in records {
                record.isHidden = false
            }
        }
        try? context.save()
    }

    func hasAnyHiddenChannels() -> Bool {
        let descriptor = FetchDescriptor<ChannelUserState>()
        if let records = try? context.fetch(descriptor) {
            return records.contains { $0.isHidden == true }
        }
        return false
    }

    func allUserStates() -> [ChannelUserState] {
        let descriptor = FetchDescriptor<ChannelUserState>()
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Updates all mutable fields of a user channel in place, preserving `dateAdded`
    /// so popularity/recency ranking is unaffected by an edit.
    func updateUserChannel(id: String, title: String, youTubeVideoID: String,
                           isLiveExpected: Bool, tagIDs: [String]) {
        let descriptor = FetchDescriptor<UserChannel>(predicate: #Predicate { $0.id == id })
        if let record = (try? context.fetch(descriptor))?.first {
            record.title = title
            record.youTubeVideoID = youTubeVideoID
            record.isLiveExpected = isLiveExpected
            record.tagIDs = tagIDs
            try? context.save()
        }
    }

    /// Adopts a curated channel into a user copy: inserts the edited `UserChannel`,
    /// migrates play history from the old curated state id to the new id,
    /// and deletes the orphaned curated state row. Upserts the new-id state row so
    /// re-adopting a previously removed video does not violate the unique constraint.
    func adoptCuratedChannel(_ edited: Channel, fromCuratedID: String) {
        addUserChannel(edited)

        let old = userState(for: fromCuratedID)
        if let target = userState(for: edited.id) {
            target.playCount = old?.playCount ?? 0
            target.lastPlayedDate = old?.lastPlayedDate
        } else {
            let target = ChannelUserState(channelID: edited.id)
            target.playCount = old?.playCount ?? 0
            target.lastPlayedDate = old?.lastPlayedDate
            context.insert(target)
        }

        if let old, old.channelID != edited.id { context.delete(old) }
        try? context.save()
    }

    // MARK: Settings (single row)
    private func settingsRecord() -> AppSettingsRecord {
        let descriptor = FetchDescriptor<AppSettingsRecord>(predicate: #Predicate { $0.id == "default" })
        if let existing = try? context.fetch(descriptor).first { return existing }
        let record = AppSettingsRecord()
        context.insert(record)
        try? context.save()
        return record
    }

    func settings() -> AppSettings {
        let r = settingsRecord()
        return AppSettings(autoResume: r.autoResume,
                           defaultSleepMinutes: r.defaultSleepMinutes,
                           showClockOverlay: r.showClockOverlay, dimLevelRaw: r.dimLevelRaw,
                           showOffline: r.showOffline,
                           defaultAutoSurfMinutes: r.defaultAutoSurfMinutes ?? 5)
    }

    func saveSettings(_ s: AppSettings) {
        let r = settingsRecord()
        r.autoResume = s.autoResume
        r.defaultSleepMinutes = s.defaultSleepMinutes
        r.showClockOverlay = s.showClockOverlay
        r.dimLevelRaw = s.dimLevelRaw
        r.showOffline = s.showOffline
        r.defaultAutoSurfMinutes = s.defaultAutoSurfMinutes
        try? context.save()
    }

    /// Records the exact channel now playing and whether the session is
    /// auto-surfing. Called on every channel start so an auto-surf session can
    /// later resume from where it drifted to.
    func saveResumeChannel(channelID: String, isAutoSurf: Bool) {
        let r = settingsRecord()
        r.lastWatchedChannelID = channelID
        r.lastSessionAutoSurf = isAutoSurf
        try? context.save()
    }

    /// Records whether a video was actively playing when the app left the
    /// foreground. Read on relaunch to decide whether to auto-play.
    func setResumeWasPlaying(_ wasPlaying: Bool) {
        settingsRecord().lastSessionWasPlaying = wasPlaying
        try? context.save()
    }

    func resumeState() -> ResumeState {
        let r = settingsRecord()
        return ResumeState(channelID: r.lastWatchedChannelID,
                           isAutoSurf: r.lastSessionAutoSurf,
                           wasPlaying: r.lastSessionWasPlaying)
    }

    // MARK: Active Guide Filter
    func selectedFilterTagIDs() -> [String] { settingsRecord().selectedTagIDs }
    func saveSelectedFilterTagIDs(_ ids: [String]) {
        settingsRecord().selectedTagIDs = ids
        try? context.save()
    }

    // MARK: Tag Usage History
    func incrementTagTapCount(tagID: String) {
        let descriptor = FetchDescriptor<TagUsageRecord>(predicate: #Predicate { $0.tagID == tagID })
        if let record = (try? context.fetch(descriptor))?.first {
            record.tapCount += 1
        } else {
            context.insert(TagUsageRecord(tagID: tagID, tapCount: 1))
        }
        try? context.save()
    }

    func tagTapCounts() -> [String: Int] {
        let descriptor = FetchDescriptor<TagUsageRecord>()
        let records = (try? context.fetch(descriptor)) ?? []
        var dict: [String: Int] = [:]
        for r in records {
            dict[r.tagID] = r.tapCount
        }
        return dict
    }
}
