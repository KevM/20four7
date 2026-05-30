import Foundation

private enum JSON {
    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

struct CatalogManifest: Codable, Sendable {
    let schemaVersion: Int
    let catalogVersion: Int
    let catalogUrl: URL
    let minAppVersion: String?
    let publishedAt: Date?

    static func decode(from data: Data) throws -> CatalogManifest {
        try JSON.decoder().decode(CatalogManifest.self, from: data)
    }
}

struct TagDefinition: Codable, Sendable {
    let name: String
    let symbol: String?
    let sortOrder: Int
}

struct CatalogChannel: Codable, Sendable {
    let id: String
    let title: String
    let youTubeVideoID: String
    let thumbnailURL: URL?
    let isLiveExpected: Bool
    let tagIds: [String]
}

struct Catalog: Codable, Sendable {
    let schemaVersion: Int
    let tags: [String: TagDefinition]
    let channels: [CatalogChannel]

    static func decode(from data: Data) throws -> Catalog {
        try JSON.decoder().decode(Catalog.self, from: data)
    }

    /// Editorial tags as `Tag` values, sorted by `sortOrder` then name.
    func editorialTags() -> [Tag] {
        tags.map { id, def in
            Tag(id: id, name: def.name, symbol: def.symbol, kind: .editorial, sortOrder: def.sortOrder)
        }
        .sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
    }

    /// Catalog channels as in-memory `Channel`s tagged `.curated`.
    func asChannels() -> [Channel] {
        channels.map { c in
            Channel(
                id: c.id,
                title: c.title,
                youTubeVideoID: c.youTubeVideoID,
                thumbnailURL: c.thumbnailURL,
                source: .curated,
                isLiveExpected: c.isLiveExpected,
                tagIDs: c.tagIds
            )
        }
    }
}
