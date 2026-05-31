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
        s.autoResume = true
        s.defaultSleepMinutes = 45
        s.showOffline = true
        store.saveSettings(s)
        XCTAssertTrue(store.settings().autoResume)
        XCTAssertEqual(store.settings().defaultSleepMinutes, 45)
        XCTAssertTrue(store.settings().showOffline)
    }
}
