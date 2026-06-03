import XCTest
@testable import TwentyFourSeven

final class CatalogValidatorTests: XCTestCase {
    private func makeCatalog(schema: Int, channels: [CatalogChannel], tags: [String: TagDefinition]) -> Catalog {
        Catalog(schemaVersion: schema, tags: tags, channels: channels)
    }

    func test_rejectsNewerSchema() {
        let c = makeCatalog(schema: 99, channels: [], tags: [:])
        XCTAssertThrowsError(try CatalogValidator.validate(c, supportedSchema: 1)) { error in
            XCTAssertEqual(error as? CatalogValidationError, .unsupportedSchema(99))
        }
    }

    func test_rejectsEmptyChannels() {
        let c = makeCatalog(schema: 1, channels: [], tags: [:])
        XCTAssertThrowsError(try CatalogValidator.validate(c, supportedSchema: 1)) { error in
            XCTAssertEqual(error as? CatalogValidationError, .noChannels)
        }
    }

    func test_rejectsUnknownTagReference() {
        let ch = CatalogChannel(id: "c1", title: "T", youTubeVideoID: "abcdefghijk",
                                thumbnailURL: nil, isLiveExpected: true, tagIds: ["ghost"])
        let c = makeCatalog(schema: 1, channels: [ch], tags: [:])
        XCTAssertThrowsError(try CatalogValidator.validate(c, supportedSchema: 1)) { error in
            XCTAssertEqual(error as? CatalogValidationError, .unknownTag(channelID: "c1", tagID: "ghost"))
        }
    }

    func test_acceptsValidCatalog() throws {
        let ch = CatalogChannel(id: "c1", title: "T", youTubeVideoID: "abcdefghijk",
                                thumbnailURL: nil, isLiveExpected: true, tagIds: ["rain"])
        let c = makeCatalog(schema: 1, channels: [ch],
                            tags: ["rain": TagDefinition(name: "Rain", symbol: nil, sortOrder: 1)])
        XCTAssertNoThrow(try CatalogValidator.validate(c, supportedSchema: 1))
    }

    func test_rejectsInvalidVideoID() {
        let ch = CatalogChannel(id: "c1", title: "T", youTubeVideoID: "invalid_id_!!",
                                thumbnailURL: nil, isLiveExpected: true, tagIds: ["rain"])
        let c = makeCatalog(schema: 1, channels: [ch],
                            tags: ["rain": TagDefinition(name: "Rain", symbol: nil, sortOrder: 1)])
        XCTAssertThrowsError(try CatalogValidator.validate(c, supportedSchema: 1)) { error in
            XCTAssertEqual(error as? CatalogValidationError, .invalidVideoID(channelID: "c1", videoID: "invalid_id_!!"))
        }
    }

    func test_rejectsManifestHostMismatch() {
        let manifest = CatalogManifest(schemaVersion: 1, catalogVersion: 7,
                                       catalogUrl: URL(string: "https://badhost.com/catalog.json")!,
                                       minAppVersion: nil, publishedAt: nil)
        XCTAssertThrowsError(try CatalogValidator.validateManifest(manifest, expectedHost: "20four7.fm.rodeo")) { error in
            XCTAssertEqual(error as? CatalogValidationError, .invalidCatalogHost)
        }
    }

    func test_acceptsMatchingManifestHost() throws {
        let manifest = CatalogManifest(schemaVersion: 1, catalogVersion: 7,
                                       catalogUrl: URL(string: "https://20four7.fm.rodeo/catalog.json")!,
                                       minAppVersion: nil, publishedAt: nil)
        XCTAssertNoThrow(try CatalogValidator.validateManifest(manifest, expectedHost: "20four7.fm.rodeo"))
    }
}
