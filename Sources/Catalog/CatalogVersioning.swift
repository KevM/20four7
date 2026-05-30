import Foundation

enum CatalogVersioning {
    static func shouldUpdate(cached: Int?, remote: Int) -> Bool {
        guard let cached else { return true }
        return remote > cached
    }

    /// Semantic-ish comparison: dotted integer components.
    static func appSatisfies(minVersion: String?, appVersion: String) -> Bool {
        guard let minVersion else { return true }
        return compare(appVersion, minVersion) >= 0
    }

    private static func compare(_ a: String, _ b: String) -> Int {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x < y ? -1 : 1 }
        }
        return 0
    }
}
