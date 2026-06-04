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
    var isLiveExpectedOverride: Bool?
    var isHidden: Bool?
    var customTitle: String?
    var playCount: Int?
    var lastPlayedDate: Date?
    var watchSeconds: Double?

    init(
        channelID: String,
        isFavorite: Bool = false,
        customOrder: Int = 0,
        userTagIDs: [String] = [],
        userID: String? = nil,
        isLiveExpectedOverride: Bool? = nil,
        isHidden: Bool? = nil,
        customTitle: String? = nil,
        playCount: Int? = 0,
        lastPlayedDate: Date? = nil,
        watchSeconds: Double? = 0
    ) {
        self.channelID = channelID
        self.isFavorite = isFavorite
        self.customOrder = customOrder
        self.userTagIDs = userTagIDs
        self.userID = userID
        self.isLiveExpectedOverride = isLiveExpectedOverride
        self.isHidden = isHidden
        self.customTitle = customTitle
        self.playCount = playCount
        self.lastPlayedDate = lastPlayedDate
        self.watchSeconds = watchSeconds
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
    var showOffline: Bool
    var lastWatchedChannelID: String?
    var defaultAutoSurfMinutes: Int?
    // Active guide filter tags, restored across launches.
    var selectedTagIDs: [String] = []

    // Resume bookkeeping: the exact last channel (including auto-surf drift),
    // whether the last session was auto-surfing, and whether a video was
    // actively playing when the app last left the foreground.
    var lastSessionAutoSurf: Bool = false
    var lastSessionWasPlaying: Bool = false

    init(id: String = "default", autoResume: Bool = false,
         defaultSleepMinutes: Int = 30, showClockOverlay: Bool = false,
         dimLevelRaw: Int = 0, showOffline: Bool = false,
         lastWatchedChannelID: String? = nil, defaultAutoSurfMinutes: Int? = nil,
         selectedTagIDs: [String] = []) {
        self.id = id
        self.autoResume = autoResume
        self.defaultSleepMinutes = defaultSleepMinutes
        self.showClockOverlay = showClockOverlay
        self.dimLevelRaw = dimLevelRaw
        self.showOffline = showOffline
        self.lastWatchedChannelID = lastWatchedChannelID
        self.defaultAutoSurfMinutes = defaultAutoSurfMinutes
        self.selectedTagIDs = selectedTagIDs
    }
}

@Model
final class TagUsageRecord {
    @Attribute(.unique) var tagID: String
    var tapCount: Int

    init(tagID: String, tapCount: Int = 0) {
        self.tagID = tagID
        self.tapCount = tapCount
    }
}

