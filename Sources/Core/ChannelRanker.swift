import Foundation

/// Single source of truth for channel popularity ranking. Pure and deterministic
/// so it can be unit-tested without persistence or network.
///
/// score = playCount
///       + dwellWeight * log2(1 + watchHours)   // bounded/fair dwell term
///       + recencyMax * (1 - age/recencyWindow) // linear 7-day recency decay
enum ChannelRanker {
    /// Recency decays linearly to 0 over this window (7 days).
    static let recencyWindow: TimeInterval = 604_800
    /// Maximum recency contribution at age 0.
    static let recencyMax: Double = 10
    /// Multiplier on the log-compressed watch-hours term. Tuned so a ~2-day
    /// continuous session (~22 pts) tops a tag while staying bounded.
    static let dwellWeight: Double = 4.0

    static func score(playCount: Int,
                      watchSeconds: Double,
                      lastPlayedDate: Date?,
                      dateAdded: Date,
                      now: Date) -> Double {
        let watchHours = max(0, watchSeconds) / 3600.0
        let dwellBoost = dwellWeight * log2(1 + watchHours)

        let reference = lastPlayedDate ?? dateAdded
        let age = now.timeIntervalSince(reference)
        let recencyBoost: Double
        if age >= 0 && age < recencyWindow {
            recencyBoost = recencyMax * (1 - age / recencyWindow)
        } else {
            recencyBoost = 0
        }

        return Double(playCount) + dwellBoost + recencyBoost
    }
}
