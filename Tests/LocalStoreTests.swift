import XCTest
import SwiftData
@testable import TwentyFourSeven

@MainActor
final class LocalStoreTests: XCTestCase {
    private func makeStore() throws -> LocalStore {
        let container = try Persistence.makeContainer(inMemory: true)
        return LocalStore(context: container.mainContext)
    }

    func test_addAndFetchUserChannel() throws {
        let store = try makeStore()
        let channel = Channel(id: "u1", title: "My Rain", youTubeVideoID: "abcdefghijk",
                              source: .user, isLiveExpected: true, tagIDs: ["mine"])
        store.addUserChannel(channel)
        let fetched = store.userChannels()
        XCTAssertEqual(fetched.map(\.id), ["u1"])
        XCTAssertEqual(fetched.first?.source, .user)
    }

    func test_toggleFavoritePersists() throws {
        let store = try makeStore()
        store.setFavorite(channelID: "c1", isFavorite: true)
        XCTAssertTrue(store.isFavorite(channelID: "c1"))
        store.setFavorite(channelID: "c1", isFavorite: false)
        XCTAssertFalse(store.isFavorite(channelID: "c1"))
    }

    func test_resumeStateRoundTrips() throws {
        let store = try makeStore()

        // Defaults before anything is written.
        XCTAssertEqual(store.resumeState(),
                       ResumeState(channelID: nil, isAutoSurf: false, wasPlaying: false))

        store.saveResumeChannel(channelID: "ch1", isAutoSurf: true)
        store.setResumeWasPlaying(true)
        XCTAssertEqual(store.resumeState(),
                       ResumeState(channelID: "ch1", isAutoSurf: true, wasPlaying: true))

        // Fields update independently.
        store.saveResumeChannel(channelID: "ch2", isAutoSurf: false)
        store.setResumeWasPlaying(false)
        XCTAssertEqual(store.resumeState(),
                       ResumeState(channelID: "ch2", isAutoSurf: false, wasPlaying: false))
    }

    func test_settingsRoundTrip() throws {
        let store = try makeStore()
        var s = store.settings()
        XCTAssertFalse(s.showOffline)
        XCTAssertEqual(s.defaultAutoSurfMinutes, 5)
        s.autoResume = true
        s.defaultSleepMinutes = 45
        s.showOffline = true
        s.defaultAutoSurfMinutes = 10
        store.saveSettings(s)
        XCTAssertTrue(store.settings().autoResume)
        XCTAssertEqual(store.settings().defaultSleepMinutes, 45)
        XCTAssertTrue(store.settings().showOffline)
        XCTAssertEqual(store.settings().defaultAutoSurfMinutes, 10)
    }

    func test_settingsDefaultAutoSurfMinutes() throws {
        let store = try makeStore()
        let settings = store.settings()
        XCTAssertEqual(settings.defaultAutoSurfMinutes, 5)
    }

    func test_tagUsageHistoryRoundTripsAndIncrements() throws {
        let store = try makeStore()
        
        // 1. Verify default is empty
        XCTAssertEqual(store.tagTapCounts(), [:])
        
        // 2. Increment and verify count is 1
        store.incrementTagTapCount(tagID: "lofi")
        XCTAssertEqual(store.tagTapCounts()["lofi"], 1)
        
        // 3. Increment again and verify count is 2
        store.incrementTagTapCount(tagID: "lofi")
        XCTAssertEqual(store.tagTapCounts()["lofi"], 2)
        
        // 4. Increment different tag
        store.incrementTagTapCount(tagID: "rain")
        XCTAssertEqual(store.tagTapCounts()["lofi"], 2)
        XCTAssertEqual(store.tagTapCounts()["rain"], 1)
    }

    func test_updateUserChannelInPlace() throws {
        let store = try makeStore()
        let channel = Channel(id: "u1", title: "Old", youTubeVideoID: "abcdefghijk",
                              source: .user, isLiveExpected: true,
                              dateAdded: Date(timeIntervalSince1970: 1000), tagIDs: ["old"])
        store.addUserChannel(channel)

        store.updateUserChannel(id: "u1", title: "New", youTubeVideoID: "abcdefghijk",
                                isLiveExpected: false, tagIDs: ["new", "cozy"])

        let fetched = store.userChannels()
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.title, "New")
        XCTAssertEqual(fetched.first?.isLiveExpected, false)
        XCTAssertEqual(fetched.first?.tagIDs, ["new", "cozy"])
        // dateAdded is preserved (ranking stays stable).
        XCTAssertEqual(fetched.first?.dateAdded, Date(timeIntervalSince1970: 1000))
    }

    func test_adoptCuratedChannelMigratesState() throws {
        let store = try makeStore()

        // Existing per-channel state under the curated id "c1".
        store.setFavorite(channelID: "c1", isFavorite: true)
        _ = store.incrementPlayCount(channelID: "c1") // playCount 1, sets lastPlayedDate

        let edited = Channel(id: "user-abcdefghijk", title: "My Rain",
                             youTubeVideoID: "abcdefghijk", source: .user,
                             isLiveExpected: false, dateAdded: Date(timeIntervalSince1970: 0),
                             tagIDs: ["rain", "cozy"])
        store.adoptCuratedChannel(edited, fromCuratedID: "c1")

        // New user channel exists with edited fields.
        let channels = store.userChannels()
        XCTAssertEqual(channels.map(\.id), ["user-abcdefghijk"])
        XCTAssertEqual(channels.first?.title, "My Rain")
        XCTAssertEqual(channels.first?.tagIDs, ["rain", "cozy"])

        // Play history migrated to the new id.
        let states = store.allUserStates()
        let newState = states.first { $0.channelID == "user-abcdefghijk" }
        XCTAssertEqual(newState?.playCount, 1)
        XCTAssertNotNil(newState?.lastPlayedDate)

        // Old curated state row is deleted.
        XCTAssertNil(states.first { $0.channelID == "c1" })
    }

    func test_recordWatchAccumulatesAndStampsDate() throws {
        let store = try makeStore()
        let d1 = Date(timeIntervalSince1970: 1000)
        let r1 = store.recordWatch(channelID: "c1", seconds: 30, date: d1)
        XCTAssertEqual(r1.watchSeconds, 30, accuracy: 0.0001)
        XCTAssertEqual(r1.lastPlayedDate, d1)

        let d2 = Date(timeIntervalSince1970: 2000)
        let r2 = store.recordWatch(channelID: "c1", seconds: 45, date: d2)
        XCTAssertEqual(r2.watchSeconds, 75, accuracy: 0.0001)
        XCTAssertEqual(r2.lastPlayedDate, d2)
    }
}
