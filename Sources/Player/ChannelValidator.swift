import Foundation

/// Add-time validation for user channels. Parsing + channel construction are pure
/// and unit-tested; embeddability is verified live by attempting to load in the
/// player (the UI surfaces `embeddingDisallowed` if YouTube rejects it).
enum ChannelValidator {
    static func parseReference(_ input: String) -> YouTubeReference? {
        YouTubeURLParser.parse(input)
    }

    /// Builds a `.user` channel from a video reference. Handles are not directly
    /// playable in sub-project #1 (they require API resolution to a video id).
    static func makeUserChannel(from reference: YouTubeReference, title: String,
                                tagIDs: [String], now: Date) -> Channel? {
        guard case let .video(id) = reference else { return nil }
        let resolvedTitle = title.trimmingCharacters(in: .whitespaces)
        return Channel(
            id: "user-\(id)",
            title: resolvedTitle.isEmpty ? "Untitled" : resolvedTitle,
            youTubeVideoID: id,
            source: .user,
            isLiveExpected: true,
            dateAdded: now,
            tagIDs: tagIDs
        )
    }
}
