import Foundation
import SwiftData

/// A plain value mirror of `AppSettingsRecord` used by the UI.
struct AppSettings: Equatable {
    var autoResume: Bool
    var audioOnly: Bool
    var defaultSleepMinutes: Int
    var showClockOverlay: Bool
    var dimLevelRaw: Int
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
        return AppSettings(autoResume: r.autoResume, audioOnly: r.audioOnly,
                           defaultSleepMinutes: r.defaultSleepMinutes,
                           showClockOverlay: r.showClockOverlay, dimLevelRaw: r.dimLevelRaw)
    }

    func saveSettings(_ s: AppSettings) {
        let r = settingsRecord()
        r.autoResume = s.autoResume
        r.audioOnly = s.audioOnly
        r.defaultSleepMinutes = s.defaultSleepMinutes
        r.showClockOverlay = s.showClockOverlay
        r.dimLevelRaw = s.dimLevelRaw
        try? context.save()
    }

    func setLastWatched(channelID: String) {
        settingsRecord().lastWatchedChannelID = channelID
        try? context.save()
    }
    func lastWatchedChannelID() -> String? { settingsRecord().lastWatchedChannelID }
}
