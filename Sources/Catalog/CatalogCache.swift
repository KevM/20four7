import Foundation

protocol CatalogCache {
    func loadCachedCatalog() -> (catalog: Catalog, version: Int)?
    func save(catalog: Catalog, version: Int, etag: String?)
    func cachedVersion() -> Int?
    func cachedETag() -> String?
}

/// File-backed cache in Application Support.
final class FileCatalogCache: CatalogCache {
    private let directory: URL
    private let fm = FileManager.default

    init(directory: URL? = nil) {
        self.directory = directory ?? fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Televista", isDirectory: true)
        try? fm.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    private var catalogURL: URL { directory.appendingPathComponent("catalog.json") }
    private var metaURL: URL { directory.appendingPathComponent("catalog-meta.json") }

    private struct Meta: Codable { let version: Int; let etag: String? }

    func loadCachedCatalog() -> (catalog: Catalog, version: Int)? {
        guard let data = try? Data(contentsOf: catalogURL),
              let catalog = try? Catalog.decode(from: data),
              let version = cachedVersion() else { return nil }
        return (catalog, version)
    }

    func save(catalog: Catalog, version: Int, etag: String?) {
        guard let data = try? JSONEncoder().encode(catalog) else { return }
        try? data.write(to: catalogURL, options: .atomic)
        let meta = try? JSONEncoder().encode(Meta(version: version, etag: etag))
        try? meta?.write(to: metaURL, options: .atomic)
    }

    private func meta() -> Meta? {
        guard let data = try? Data(contentsOf: metaURL) else { return nil }
        return try? JSONDecoder().decode(Meta.self, from: data)
    }
    func cachedVersion() -> Int? { meta()?.version }
    func cachedETag() -> String? { meta()?.etag }
}
