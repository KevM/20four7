import XCTest
@testable import TwentyFourSeven

/// In-memory cache double.
final class MemoryCatalogCache: CatalogCache {
    var catalog: Catalog?
    var version: Int?
    var etag: String?
    func loadCachedCatalog() -> (catalog: Catalog, version: Int)? {
        guard let catalog, let version else { return nil }
        return (catalog, version)
    }
    func save(catalog: Catalog, version: Int, etag: String?) {
        self.catalog = catalog; self.version = version; self.etag = etag
    }
    func cachedVersion() -> Int? { version }
    func cachedETag() -> String? { etag }
}

/// URLProtocol stub that returns canned responses keyed by path suffix.
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var routes: [String: (status: Int, body: Data, headers: [String: String])] = [:]
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url?.lastPathComponent ?? ""
        let route = StubURLProtocol.routes[path] ?? (404, Data(), [:])
        let resp = HTTPURLResponse(url: request.url!, statusCode: route.status,
                                   httpVersion: nil, headerFields: route.headers)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: route.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class RemoteConfigTests: XCTestCase {
    private func session() -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: cfg)
    }

    private let manifestJSON = """
    {"schemaVersion":1,"catalogVersion":7,
     "catalogUrl":"https://cdn.example.com/20four7/catalog-v7.json","minAppVersion":"1.0.0"}
    """.data(using: .utf8)!

    private let catalogJSON = """
    {"schemaVersion":1,
     "tags":{"rain":{"name":"Rain","symbol":"cloud.rain","sortOrder":1}},
     "channels":[{"id":"c1","title":"Rain","youTubeVideoID":"abcdefghijk",
       "thumbnailURL":null,"isLiveExpected":true,"tagIds":["rain"]}]}
    """.data(using: .utf8)!

    override func tearDown() { StubURLProtocol.routes = [:]; super.tearDown() }

    func test_fetchesAndCachesNewerCatalog() async throws {
        StubURLProtocol.routes = [
            "channels-manifest.json": (200, manifestJSON, ["ETag": "v7etag"]),
            "catalog-v7.json": (200, catalogJSON, [:]),
        ]
        let cache = MemoryCatalogCache()
        let rc = RemoteConfig(baseURL: Config.catalogBaseURL, session: session(),
                              cache: cache, supportedSchema: 1, appVersion: "1.0.0",
                              bundledLoader: { fatalError("not used") })
        let catalog = try await rc.currentCatalog()
        XCTAssertEqual(catalog.channels.first?.id, "c1")
        XCTAssertEqual(cache.cachedVersion(), 7)
    }

    func test_fallsBackToCacheOnNetworkFailure() async throws {
        // No routes => 404 for everything. Cache already has v6.
        let cache = MemoryCatalogCache()
        let cached = try Catalog.decode(from: catalogJSON)
        cache.save(catalog: cached, version: 6, etag: nil)
        let rc = RemoteConfig(baseURL: Config.catalogBaseURL, session: session(),
                              cache: cache, supportedSchema: 1, appVersion: "1.0.0",
                              bundledLoader: { fatalError("not used") })
        let catalog = try await rc.currentCatalog()
        XCTAssertEqual(catalog.channels.first?.id, "c1")
    }

    func test_fallsBackToBundledWhenNoCache() async throws {
        let bundled = try Catalog.decode(from: catalogJSON)
        let rc = RemoteConfig(baseURL: Config.catalogBaseURL, session: session(),
                              cache: MemoryCatalogCache(), supportedSchema: 1, appVersion: "1.0.0",
                              bundledLoader: { bundled })
        let catalog = try await rc.currentCatalog()
        XCTAssertEqual(catalog.channels.first?.id, "c1")
    }
}
