import XCTest
import Combine
@testable import TwentyFourSeven

@MainActor
final class PlaybackControllerTests: XCTestCase {
    private func makeChannels() -> [Channel] {
        ["a", "b", "c"].map {
            Channel(id: $0, title: $0, youTubeVideoID: "v\($0)", source: .curated, isLiveExpected: true)
        }
    }

    func test_playLoadsChannel() {
        let player = MockPlayerService()
        let clock = ManualClock()
        let c = PlaybackController(player: player, clock: clock)
        c.setLineup(makeChannels())
        c.play(channelID: "b")
        XCTAssertEqual(c.currentChannel?.id, "b")
        XCTAssertEqual(player.loadedChannel?.id, "b")
    }

    func test_surfMovesToNextAndLoads() {
        let player = MockPlayerService()
        let c = PlaybackController(player: player, clock: ManualClock())
        c.setLineup(makeChannels())
        c.play(channelID: "a")
        c.surf(.next)
        XCTAssertEqual(c.currentChannel?.id, "b")
        XCTAssertEqual(player.loadedChannel?.id, "b")
    }

    func test_sleepTimerPausesAfterInterval() {
        let player = MockPlayerService()
        let clock = ManualClock()
        let c = PlaybackController(player: player, clock: clock)
        c.setLineup(makeChannels())
        c.play(channelID: "a")
        c.startSleepTimer(seconds: 60)
        clock.advance(by: 59)
        XCTAssertNotEqual(player.lastCommand, .pause)
        clock.advance(by: 1)
        XCTAssertEqual(player.lastCommand, .pause)
    }

    func test_offlineEventOffersSurf() {
        let player = MockPlayerService()
        let c = PlaybackController(player: player, clock: ManualClock())
        c.setLineup(makeChannels())
        c.play(channelID: "a")
        player.simulate(event: .streamOffline)
        XCTAssertTrue(c.showsOfflineState)
    }

    func test_playingOfflineChannelShowsOfflineStateImmediately() throws {
        let player = MockPlayerService()
        let container = try Persistence.makeContainer(inMemory: true)
        let localStore = LocalStore(context: container.mainContext)
        let remoteConfig = RemoteConfig(
            baseURL: Config.catalogBaseURL, session: .shared, cache: MemoryCatalogCache(),
            supportedSchema: 1, appVersion: "1.0.0", bundledLoader: { Catalog(schemaVersion: 1, tags: [:], channels: []) }
        )
        let store = ChannelStore(remoteConfig: remoteConfig, localStore: localStore)
        
        let c = PlaybackController(player: player, clock: ManualClock(), channelStore: store)
        let offlineChannel = Channel(id: "off", title: "Offline", youTubeVideoID: "123", source: .curated, isLiveExpected: true)
        c.setLineup([offlineChannel])
        
        store.markChannelOffline(id: "off")
        c.play(channelID: "off")
        XCTAssertTrue(c.showsOfflineState)
        
        // Once playback starts, showsOfflineState should become false, and it should be marked online in the store
        player.simulate(event: .playbackStarted)
        XCTAssertFalse(c.showsOfflineState)
        XCTAssertFalse(store.offlineChannelIDs.contains("off"))
    }

    func test_offlineEventMarksChannelOfflineInStore() throws {
        let player = MockPlayerService()
        let container = try Persistence.makeContainer(inMemory: true)
        let localStore = LocalStore(context: container.mainContext)
        let remoteConfig = RemoteConfig(
            baseURL: Config.catalogBaseURL, session: .shared, cache: MemoryCatalogCache(),
            supportedSchema: 1, appVersion: "1.0.0", bundledLoader: { Catalog(schemaVersion: 1, tags: [:], channels: []) }
        )
        let store = ChannelStore(remoteConfig: remoteConfig, localStore: localStore)
        
        let c = PlaybackController(player: player, clock: ManualClock(), channelStore: store)
        let channel = Channel(id: "ch1", title: "Test", youTubeVideoID: "123", source: .curated, isLiveExpected: true)
        c.setLineup([channel])
        
        c.play(channelID: "ch1")
        XCTAssertFalse(store.offlineChannelIDs.contains("ch1"))
        
        player.simulate(event: .streamOffline)
        XCTAssertTrue(c.showsOfflineState)
        XCTAssertTrue(store.offlineChannelIDs.contains("ch1"))
    }

    func test_isCurrentlyLiveUpdatesOnEvent() {
        let player = MockPlayerService()
        let c = PlaybackController(player: player, clock: ManualClock())
        let liveChannel = Channel(id: "ch1", title: "Live", youTubeVideoID: "123", source: .curated, isLiveExpected: true)
        c.setLineup([liveChannel])
        
        // Starts with isLiveExpected (true)
        c.play(channelID: "ch1")
        XCTAssertTrue(c.isCurrentlyLive)
        
        // Simulates detecting it is NOT live
        player.simulate(event: .liveStatusDetected(isLive: false))
        XCTAssertFalse(c.isCurrentlyLive)
        
        // Simulates detecting it IS live
        player.simulate(event: .liveStatusDetected(isLive: true))
        XCTAssertTrue(c.isCurrentlyLive)
    }
}
