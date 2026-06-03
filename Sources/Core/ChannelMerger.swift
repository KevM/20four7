import Foundation

enum ChannelMerger {
    /// Curated + user channels into one list. On duplicate `youTubeVideoID`, the
    /// user-added channel wins (their tags/title override the curated entry).
    /// ChannelUserState overrides (favorites, custom status, and hides) are applied.
    static func merge(curated: [Channel], user: [Channel], userStates: [ChannelUserState] = []) -> [Channel] {
        var byVideo: [String: Channel] = [:]
        for c in curated { byVideo[c.youTubeVideoID] = c }
        for u in user { byVideo[u.youTubeVideoID] = u }  // user overrides
        
        let statesByChannelID = Dictionary(uniqueKeysWithValues: userStates.map { ($0.channelID, $0) })
        
        var merged: [Channel] = []
        for channel in byVideo.values {
            if let state = statesByChannelID[channel.id] {
                // If it is hidden, skip it.
                if state.isHidden == true {
                    continue
                }
                
                var modified = channel
                if let liveOverride = state.isLiveExpectedOverride {
                    modified.isLiveExpected = liveOverride
                }
                if let titleOverride = state.customTitle {
                    modified.title = titleOverride
                }
                modified.playCount = state.playCount ?? 0
                modified.lastPlayedDate = state.lastPlayedDate
                // Favorited channels carry the derived favs id at runtime only (never
                // persisted), so TagFilter and the chip bar treat favs like any other tag.
                if state.isFavorite, !modified.tagIDs.contains(Tag.favsID) {
                    modified.tagIDs.append(Tag.favsID)
                }
                merged.append(modified)
            } else {
                merged.append(channel)
            }
        }
        return merged
    }
}
