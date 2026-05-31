import Foundation
import SwiftData

@Model
final class UserChannel {
    @Attribute(.unique) var id: String
    var title: String
    var youTubeVideoID: String
    var thumbnailURLString: String?
    var isLiveExpected: Bool
    var dateAdded: Date
    var tagIDs: [String]
    /// Nil in sub-project #1; Sign in with Apple populates it for CloudKit sync.
    var userID: String?

    init(id: String, title: String, youTubeVideoID: String, thumbnailURLString: String?,
         isLiveExpected: Bool, dateAdded: Date, tagIDs: [String], userID: String?) {
        self.id = id
        self.title = title
        self.youTubeVideoID = youTubeVideoID
        self.thumbnailURLString = thumbnailURLString
        self.isLiveExpected = isLiveExpected
        self.dateAdded = dateAdded
        self.tagIDs = tagIDs
        self.userID = userID
    }
}

@Model
final class ChannelUserState {
    @Attribute(.unique) var channelID: String
    var isFavorite: Bool
    var customOrder: Int
    var userTagIDs: [String]
    var userID: String?

    init(channelID: String, isFavorite: Bool = false, customOrder: Int = 0,
         userTagIDs: [String] = [], userID: String? = nil) {
        self.channelID = channelID
        self.isFavorite = isFavorite
        self.customOrder = customOrder
        self.userTagIDs = userTagIDs
        self.userID = userID
    }
}

@Model
final class AppSettingsRecord {
    // Single-row record keyed by a constant id.
    @Attribute(.unique) var id: String
    var autoResume: Bool
    var defaultSleepMinutes: Int
    var showClockOverlay: Bool
    var dimLevelRaw: Int   // 0 none, 1 low, 2 medium, 3 high
    var lastWatchedChannelID: String?

    init(id: String = "default", autoResume: Bool = false,
         defaultSleepMinutes: Int = 30, showClockOverlay: Bool = false,
         dimLevelRaw: Int = 0, lastWatchedChannelID: String? = nil) {
        self.id = id
        self.autoResume = autoResume
        self.defaultSleepMinutes = defaultSleepMinutes
        self.showClockOverlay = showClockOverlay
        self.dimLevelRaw = dimLevelRaw
        self.lastWatchedChannelID = lastWatchedChannelID
    }
}
