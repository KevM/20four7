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
