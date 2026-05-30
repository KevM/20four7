import XCTest
@testable import TwentyFourSeven

final class CatalogModelsTests: XCTestCase {
    func test_decodesManifest() throws {
        let json = """
        {
          "schemaVersion": 1,
          "catalogVersion": 7,
          "catalogUrl": "https://cdn.example.com/20four7/catalog-v7.json",
          "minAppVersion": "1.0.0",
          "publishedAt": "2026-05-30T00:00:00Z"
        }
        """.data(using: .utf8)!
        let manifest = try CatalogManifest.decode(from: json)
        XCTAssertEqual(manifest.catalogVersion, 7)
        XCTAssertEqual(manifest.catalogUrl.lastPathComponent, "catalog-v7.json")
        XCTAssertEqual(manifest.minAppVersion, "1.0.0")
    }

    func test_decodesCatalogAndMapsToChannels() throws {
        let json = """
        {
          "schemaVersion": 1,
          "tags": { "rain": { "name": "Rain", "symbol": "cloud.rain", "sortOrder": 20 } },
          "channels": [
            { "id": "c1", "title": "Rain on Window", "youTubeVideoID": "abc",
              "thumbnailURL": null, "isLiveExpected": true, "tagIds": ["rain"] }
          ]
        }
        """.data(using: .utf8)!
        let catalog = try Catalog.decode(from: json)
        XCTAssertEqual(catalog.tags["rain"]?.name, "Rain")
        let channels = catalog.asChannels()
        XCTAssertEqual(channels.count, 1)
        XCTAssertEqual(channels[0].source, .curated)
        XCTAssertEqual(channels[0].tagIDs, ["rain"])
    }

    func test_resolvedTagsSortedBySortOrder() throws {
        let json = """
        {
          "schemaVersion": 1,
          "tags": {
            "b": { "name": "B", "symbol": null, "sortOrder": 20 },
            "a": { "name": "A", "symbol": null, "sortOrder": 10 }
          },
          "channels": []
        }
        """.data(using: .utf8)!
        let catalog = try Catalog.decode(from: json)
        XCTAssertEqual(catalog.editorialTags().map(\.id), ["a", "b"])
    }
}
