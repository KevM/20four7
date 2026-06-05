import Foundation

enum ChannelSearch {
    /// Free-text Guide search. The query is split into whitespace-separated
    /// tokens; a channel matches when **every** token is a substring of either
    /// its title or one of its resolved tag names (case- & diacritic-insensitive).
    /// Tokenizing means a query like "Norway Rail" matches a title such as
    /// "Norway's Railway ..." even though that exact phrase never occurs, and a
    /// token may match the title while another matches a tag name.
    /// An empty/whitespace query returns all channels unchanged.
    static func filter(_ channels: [Channel], query: String,
                       tagsByID: [String: Tag]) -> [Channel] {
        let tokens = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !tokens.isEmpty else { return channels }

        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return channels.filter { channel in
            let haystacks = [channel.title] + channel.tagIDs.compactMap { tagsByID[$0]?.name }
            return tokens.allSatisfy { token in
                haystacks.contains { $0.range(of: token, options: options) != nil }
            }
        }
    }
}
