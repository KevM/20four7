import Foundation

enum ChannelMerger {
    /// Curated + user channels into one list. On duplicate `youTubeVideoID`, the
    /// user-added channel wins (their tags/title override the curated entry).
    static func merge(curated: [Channel], user: [Channel]) -> [Channel] {
        var byVideo: [String: Channel] = [:]
        for c in curated { byVideo[c.youTubeVideoID] = c }
        for u in user { byVideo[u.youTubeVideoID] = u }  // user overrides
        return Array(byVideo.values)
    }
}
