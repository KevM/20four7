import Foundation

enum TagKind: String, Codable, Sendable {
    case editorial   // defined in the curated catalog
    case user        // created by the user, private (synced later)
    case derived     // computed (e.g. "Popular") — not present in sub-project #1
}

struct Tag: Identifiable, Hashable, Codable, Sendable {
    let id: String
    var name: String
    var symbol: String?     // SF Symbol name
    var kind: TagKind
    var sortOrder: Int

    init(id: String, name: String, symbol: String? = nil, kind: TagKind, sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.kind = kind
        self.sortOrder = sortOrder
    }
}

extension Tag {
    /// Reserved id for the derived "favs" tag (favorited channels). Never persisted;
    /// `ChannelMerger` injects it into a channel's runtime `tagIDs` when it is favorited.
    static let favsID = "favs"

    /// The derived favs chip. `sortOrder` -1 keeps it ahead of editorial (0+) and user (100) tags.
    static var favs: Tag {
        Tag(id: favsID, name: "favs", symbol: "star.fill", kind: .derived, sortOrder: -1)
    }
}
