import XCTest
@testable import TwentyFourSeven

/// Exercises the production file-backed cache (the rest of the suite uses the
/// in-memory `MemoryCatalogCache` double). Uses an injected temp directory so
/// nothing touches Application Support.
final class CatalogCacheTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CatalogCacheTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeCatalog(channelID: String = "c1") -> Catalog {
        Catalog(
            schemaVersion: 1,
            tags: ["rain": TagDefinition(name: "Rain", symbol: "cloud.rain", sortOrder: 1)],
            channels: [CatalogChannel(id: channelID, title: "Rain", youTubeVideoID: "abcdefghijk",
                                      thumbnailURL: nil, isLiveExpected: true, tagIds: ["rain"])]
        )
    }

    func test_saveThenLoadRoundTrips() {
        let cache = FileCatalogCache(directory: directory)
        cache.save(catalog: makeCatalog(), version: 7, etag: "W/\"abc\"")

        let loaded = cache.loadCachedCatalog()
        XCTAssertEqual(loaded?.version, 7)
        XCTAssertEqual(loaded?.catalog.channels.first?.id, "c1")
        XCTAssertEqual(cache.cachedVersion(), 7)
        XCTAssertEqual(cache.cachedETag(), "W/\"abc\"")
    }

    func test_loadReturnsNilWhenEmpty() {
        let cache = FileCatalogCache(directory: directory)
        XCTAssertNil(cache.loadCachedCatalog())
        XCTAssertNil(cache.cachedVersion())
        XCTAssertNil(cache.cachedETag())
    }

    func test_saveOverwritesPreviousCatalog() {
        let cache = FileCatalogCache(directory: directory)
        cache.save(catalog: makeCatalog(channelID: "old"), version: 1, etag: nil)
        cache.save(catalog: makeCatalog(channelID: "new"), version: 2, etag: nil)

        let loaded = cache.loadCachedCatalog()
        XCTAssertEqual(loaded?.version, 2)
        XCTAssertEqual(loaded?.catalog.channels.first?.id, "new")
        XCTAssertNil(cache.cachedETag())
    }

    func test_persistsAcrossInstancesInSameDirectory() {
        FileCatalogCache(directory: directory).save(catalog: makeCatalog(), version: 5, etag: "e1")

        // A fresh instance pointed at the same directory sees the persisted data.
        let reopened = FileCatalogCache(directory: directory)
        XCTAssertEqual(reopened.cachedVersion(), 5)
        XCTAssertEqual(reopened.loadCachedCatalog()?.catalog.channels.count, 1)
    }
}
