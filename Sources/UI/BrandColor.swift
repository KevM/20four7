import SwiftUI

/// App-wide brand palette, kept in sync with the marketing site (`web/index.css`).
/// `brandAccent` is the global tint applied at the app root; prefer it over
/// hard-coded colors so the accent stays consistent everywhere.
extension Color {
    /// Purple — `#a855f7` (web `--color-secondary`). The app's accent tint.
    static let brandAccent = Color(red: 168 / 255, green: 85 / 255, blue: 247 / 255)

    /// Indigo — `#6366f1` (web `--color-primary`). Reserved for gradients/pairing.
    static let brandIndigo = Color(red: 99 / 255, green: 102 / 255, blue: 241 / 255)
}
