import Foundation

enum ChannelSearch {
    /// Matches a channel if the query (trimmed, case- & diacritic-insensitive)
    /// is a substring of its title OR any of its resolved tag names.
    /// Empty/whitespace query returns all channels unchanged.
    static func filter(_ channels: [Channel], query: String,
                       tagsByID: [String: Tag]) -> [Channel] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return channels }
        
        return channels.filter { channel in
            // Title match (case & diacritic insensitive)
            if channel.title.range(of: trimmedQuery, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
                return true
            }
            // Tag name match (case & diacritic insensitive)
            for tagID in channel.tagIDs {
                if let tag = tagsByID[tagID],
                   tag.name.range(of: trimmedQuery, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
                    return true
                }
            }
            return false
        }
    }
}
