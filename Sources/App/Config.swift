import Foundation

/// Build-time constants. Replace `catalogBaseURL` per environment.
enum Config {
    /// Stable entry point host for the curated catalog. The manifest lives at
    /// `<catalogBaseURL>/channels-manifest.json`.
    static let catalogBaseURL = URL(string: "https://cdn.example.com/20four7")!

    /// Highest catalog `schemaVersion` this build understands.
    static let supportedSchemaVersion = 1
}
