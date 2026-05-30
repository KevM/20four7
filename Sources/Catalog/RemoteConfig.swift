import Foundation

/// Fetches the curated catalog with a resilience ladder:
/// live (manifest → catalog) → last good cache → bundled fallback.
///
/// `@unchecked Sendable`: all stored properties are immutable (`let`), and the
/// type is only ever driven serially from the `@MainActor` `ChannelStore`, so it
/// is safe to reference across the isolation boundary under Swift 6.
final class RemoteConfig: @unchecked Sendable {
    private let baseURL: URL
    private let session: URLSession
    private let cache: CatalogCache
    private let supportedSchema: Int
    private let appVersion: String
    private let bundledLoader: () -> Catalog

    init(baseURL: URL, session: URLSession, cache: CatalogCache,
         supportedSchema: Int, appVersion: String, bundledLoader: @escaping () -> Catalog) {
        self.baseURL = baseURL
        self.session = session
        self.cache = cache
        self.supportedSchema = supportedSchema
        self.appVersion = appVersion
        self.bundledLoader = bundledLoader
    }

    func currentCatalog() async -> Catalog {
        if let fresh = try? await fetchFromNetwork() { return fresh }
        if let cached = cache.loadCachedCatalog() { return cached.catalog }
        return bundledLoader()
    }

    private func fetchFromNetwork() async throws -> Catalog {
        let manifest = try await fetchManifest()
        guard CatalogVersioning.appSatisfies(minVersion: manifest.minAppVersion, appVersion: appVersion) else {
            throw RemoteConfigError.appTooOld
        }
        guard CatalogVersioning.shouldUpdate(cached: cache.cachedVersion(), remote: manifest.catalogVersion) else {
            if let cached = cache.loadCachedCatalog() { return cached.catalog }
            throw RemoteConfigError.noUpdateNoCache
        }
        var request = URLRequest(url: manifest.catalogUrl)
        if let etag = cache.cachedETag() { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw RemoteConfigError.badResponse }
        if http.statusCode == 304, let cached = cache.loadCachedCatalog() { return cached.catalog }
        guard http.statusCode == 200 else { throw RemoteConfigError.badResponse }
        let catalog = try Catalog.decode(from: data)
        try CatalogValidator.validate(catalog, supportedSchema: supportedSchema)
        let etag = http.value(forHTTPHeaderField: "ETag")
        cache.save(catalog: catalog, version: manifest.catalogVersion, etag: etag)
        return catalog
    }

    private func fetchManifest() async throws -> CatalogManifest {
        let url = baseURL.appendingPathComponent("channels-manifest.json")
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw RemoteConfigError.badResponse
        }
        return try CatalogManifest.decode(from: data)
    }
}

enum RemoteConfigError: Error { case badResponse, appTooOld, noUpdateNoCache }
