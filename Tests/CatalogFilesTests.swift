import XCTest
@testable import TwentyFourSeven

final class CatalogFilesTests: XCTestCase {
    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func test_fallbackCatalogIsValid() throws {
        let url = repoRoot.appendingPathComponent("Sources/Resources/catalog-fallback.json")
        let data = try Data(contentsOf: url)
        let catalog = try Catalog.decode(from: data)
        XCTAssertNoThrow(try CatalogValidator.validate(catalog, supportedSchema: Config.supportedSchemaVersion))
    }

    func test_webCatalogIsValid() throws {
        let url = repoRoot.appendingPathComponent("web/channels-catalog.json")
        let data = try Data(contentsOf: url)
        let catalog = try Catalog.decode(from: data)
        XCTAssertNoThrow(try CatalogValidator.validate(catalog, supportedSchema: Config.supportedSchemaVersion))
    }

    func test_webManifestIsValid() throws {
        let url = repoRoot.appendingPathComponent("web/channels-manifest.json")
        let data = try Data(contentsOf: url)
        let manifest = try CatalogManifest.decode(from: data)
        
        let expectedHost = Config.catalogBaseURL.host
        XCTAssertNoThrow(try CatalogValidator.validateManifest(manifest, expectedHost: expectedHost))
    }
}
