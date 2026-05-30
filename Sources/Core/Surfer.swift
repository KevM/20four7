import Foundation

enum SurfDirection { case next, previous }

enum Surfer {
    /// Channel before/after `currentID` with wrap-around. If `currentID` isn't in
    /// the list, returns the first channel. Returns nil for an empty list.
    static func channel(after currentID: String, in list: [Channel], direction: SurfDirection) -> Channel? {
        guard !list.isEmpty else { return nil }
        guard let idx = list.firstIndex(where: { $0.id == currentID }) else { return list.first }
        let count = list.count
        let target = direction == .next ? (idx + 1) % count : (idx - 1 + count) % count
        return list[target]
    }
}
