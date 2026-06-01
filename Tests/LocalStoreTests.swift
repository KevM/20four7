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

    func test_lastWatchedRoundTrips() throws {
        let store = try makeStore()
        store.setLastWatched(channelID: "c9")
        XCTAssertEqual(store.lastWatchedChannelID(), "c9")
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
}

