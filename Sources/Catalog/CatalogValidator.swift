import Foundation

enum CatalogValidationError: Error, Equatable {
    case unsupportedSchema(Int)
    case noChannels
    case unknownTag(channelID: String, tagID: String)
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
            for tagID in channel.tagIds where catalog.tags[tagID] == nil {
                throw CatalogValidationError.unknownTag(channelID: channel.id, tagID: tagID)
            }
        }
    }
}
