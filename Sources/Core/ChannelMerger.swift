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
                merged.append(modified)
            } else {
                merged.append(channel)
            }
        }
        return merged
    }
}
