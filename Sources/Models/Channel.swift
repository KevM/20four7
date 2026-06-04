import Foundation

enum ChannelSource: String, Codable, Sendable {
    case curated
    case user
}

/// In-memory channel used throughout the app. Tags are referenced by id and
/// resolved against the catalog's tag dictionary (rename-safe).
struct Channel: Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    var youTubeVideoID: String
    var thumbnailURL: URL?
    var source: ChannelSource
    var isLiveExpected: Bool
    var dateAdded: Date
    var tagIDs: [String]
    var playCount: Int
    var lastPlayedDate: Date?
    var watchSeconds: Double

    init(
        id: String,
        title: String,
        youTubeVideoID: String,
        thumbnailURL: URL? = nil,
        source: ChannelSource,
        isLiveExpected: Bool,
        dateAdded: Date = .init(timeIntervalSince1970: 0),
        tagIDs: [String] = [],
        playCount: Int = 0,
        lastPlayedDate: Date? = nil,
        watchSeconds: Double = 0
    ) {
        self.id = id
        self.title = title
        self.youTubeVideoID = youTubeVideoID
        self.thumbnailURL = thumbnailURL
        self.source = source
        self.isLiveExpected = isLiveExpected
        self.dateAdded = dateAdded
        self.tagIDs = tagIDs
        self.playCount = playCount
        self.lastPlayedDate = lastPlayedDate
        self.watchSeconds = watchSeconds
    }

    /// YouTube's default thumbnail when none is provided.
    var resolvedThumbnailURL: URL {
        thumbnailURL ?? URL(string: "https://i.ytimg.com/vi/\(youTubeVideoID)/hqdefault.jpg")!
    }
}
