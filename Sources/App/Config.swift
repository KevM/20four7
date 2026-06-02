import Foundation

/// Build-time constants. Replace `catalogBaseURL` per environment.
enum Config {
    /// Stable entry point host for the curated catalog. The manifest lives at
    /// `<catalogBaseURL>/channels-manifest.json`.
    static let catalogBaseURL = URL(string: "https://20four7.fm.rodeo")!

    /// Highest catalog `schemaVersion` this build understands.
    static let supportedSchemaVersion = 1

    /// Whether the background liveness scanner runs. Disabled for now: it drives a
    /// hidden WKWebView that sequentially autoplays YouTube embeds at launch, which
    /// hurt startup responsiveness, and curated channels are expected to stay live.
    /// Flip to `true` to restore offline detection.
    static let backgroundScanEnabled = false
}
