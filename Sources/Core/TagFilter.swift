import Foundation

enum TagFilter {
    /// Union (OR) filtering: a channel matches if it carries ANY selected tag.
    /// Empty selection returns all channels.
    static func filter(_ channels: [Channel], anyOf selected: Set<String>) -> [Channel] {
        guard !selected.isEmpty else { return channels }
        return channels.filter { !Set($0.tagIDs).isDisjoint(with: selected) }
    }

    /// Resolve a channel's tag ids into `Tag`s using the supplied dictionary,
    /// dropping unknown ids.
    static func resolve(_ tagIDs: [String], in dictionary: [String: Tag]) -> [Tag] {
        tagIDs.compactMap { dictionary[$0] }
    }
}
