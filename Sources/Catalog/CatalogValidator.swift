import Foundation

enum CatalogValidationError: Error, Equatable {
    case unsupportedSchema(Int)
    case noChannels
    case unknownTag(channelID: String, tagID: String)
    case invalidVideoID(channelID: String, videoID: String)
    case invalidCatalogHost
}

enum CatalogValidator {
    static func validate(_ catalog: Catalog, supportedSchema: Int) throws {
        guard catalog.schemaVersion <= supportedSchema else {
            throw CatalogValidationError.unsupportedSchema(catalog.schemaVersion)
        }
        guard !catalog.channels.isEmpty else {
            throw CatalogValidationError.noChannels
        }
        for channel in catalog.channels {
            guard YouTubeURLParser.isValidVideoID(channel.youTubeVideoID) else {
                throw CatalogValidationError.invalidVideoID(channelID: channel.id, videoID: channel.youTubeVideoID)
            }
            for tagID in channel.tagIds where catalog.tags[tagID] == nil {
                throw CatalogValidationError.unknownTag(channelID: channel.id, tagID: tagID)
            }
        }
    }

    static func validateManifest(_ manifest: CatalogManifest, expectedHost: String?) throws {
        guard manifest.catalogUrl.host == expectedHost else {
            throw CatalogValidationError.invalidCatalogHost
        }
    }
}
