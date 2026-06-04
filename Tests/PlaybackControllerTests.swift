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

    func test_playPropagatesStartTime() {
        let player = MockPlayerService()
        let clock = ManualClock()
        let c = PlaybackController(player: player, clock: clock)
        c.setLineup(makeChannels())
        c.play(channelID: "b", startTime: 123.45)
        XCTAssertEqual(c.currentChannel?.id, "b")
        XCTAssertEqual(player.loadedChannel?.id, "b")
        XCTAssertEqual(player.loadedStartTime, 123.45)
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

    func test_autoSurfTimerTriggersSurf() {
        let player = MockPlayerService()
        let clock = ManualClock()
        let c = PlaybackController(player: player, clock: clock)
        let channels = makeChannels()
        c.setLineup(channels)
        c.play(channelID: "a")
        
        c.startAutoSurf(interval: 10)
        XCTAssertTrue(c.isAutoSurfActive)
        XCTAssertEqual(c.autoSurfTimeRemaining, 10)
        
        clock.advance(by: 5)
        XCTAssertEqual(c.autoSurfTimeRemaining, 5)
        XCTAssertEqual(c.currentChannel?.id, "a")
        
        clock.advance(by: 5)
        XCTAssertEqual(c.currentChannel?.id, "b")
        XCTAssertEqual(c.autoSurfTimeRemaining, 10) // resets to interval
    }

    func test_autoSurfTimerPausesOnPlayerPause() {
        let player = MockPlayerService()
        let clock = ManualClock()
        let c = PlaybackController(player: player, clock: clock)
        c.setLineup(makeChannels())
        c.play(channelID: "a")
        
        c.startAutoSurf(interval: 10)
        clock.advance(by: 3)
        XCTAssertEqual(c.autoSurfTimeRemaining, 7)
        
        c.pauseFromUI()
        clock.advance(by: 5)
        XCTAssertEqual(c.autoSurfTimeRemaining, 7) // paused, doesn't decrement
        
        c.playFromUI()
        clock.advance(by: 2)
        XCTAssertEqual(c.autoSurfTimeRemaining, 5) // resumed, decrements again
    }

    func test_autoSurfTimerResetsOnManualSurf() {
        let player = MockPlayerService()
        let clock = ManualClock()
        let c = PlaybackController(player: player, clock: clock)
        c.setLineup(makeChannels())
        c.play(channelID: "a")
        
        c.startAutoSurf(interval: 10)
        clock.advance(by: 4)
        XCTAssertEqual(c.autoSurfTimeRemaining, 6)
        
        c.surf(.next)
        XCTAssertEqual(c.autoSurfTimeRemaining, 10) // manual surf resets timer
    }

    func test_autoSurfTimerDisablesOnSurfFailure() {
        let player = MockPlayerService()
        let clock = ManualClock()
        let c = PlaybackController(player: player, clock: clock)
        c.setLineup(makeChannels())
        c.play(channelID: "a")
        
        c.startAutoSurf(interval: 10)
        XCTAssertTrue(c.isAutoSurfActive)
        
        c.setLineup([])
        c.surf(.next)
        
        XCTAssertFalse(c.isAutoSurfActive)
        XCTAssertNil(c.autoSurfTimeRemaining)
    }

    func test_autoSurfTimerDisablesOnAutoSurfFailure() {
        let player = MockPlayerService()
        let clock = ManualClock()
        let c = PlaybackController(player: player, clock: clock)
        c.setLineup(makeChannels())
        c.play(channelID: "a")
        
        c.startAutoSurf(interval: 10)
        XCTAssertTrue(c.isAutoSurfActive)
        
        c.setLineup([])
        clock.advance(by: 10)
        
        XCTAssertFalse(c.isAutoSurfActive)
        XCTAssertNil(c.autoSurfTimeRemaining)
    }

    func test_autoSurfTimerDoesNotDecrementWhileNotPlaying() {
        let player = MockPlayerService()
        let clock = ManualClock()
        let c = PlaybackController(player: player, clock: clock)
        c.setLineup(makeChannels())
        c.play(channelID: "a")
        
        // Explicitly set state to .loading to test non-playing behavior
        player.simulate(state: .loading)
        XCTAssertEqual(c.state, .loading)
        
        c.startAutoSurf(interval: 10)
        XCTAssertTrue(c.isAutoSurfActive)
        XCTAssertEqual(c.autoSurfTimeRemaining, 10)
        
        // Does not decrement when not .playing
        clock.advance(by: 5)
        XCTAssertEqual(c.autoSurfTimeRemaining, 10)
        
        // Simulates playing state
        player.simulate(state: .playing)
        XCTAssertEqual(c.state, .playing)
        
        // Now it decrements
        clock.advance(by: 3)
        XCTAssertEqual(c.autoSurfTimeRemaining, 7)
    }

    func test_onChannelChangedUserInitiatedFlag() {
        let player = MockPlayerService()
        let clock = ManualClock()
        let c = PlaybackController(player: player, clock: clock)
        c.setLineup(makeChannels())

        var changes: [(id: String, userInitiated: Bool)] = []
        c.onChannelChanged = { channel, userInitiated in
            changes.append((channel.id, userInitiated))
        }

        // Tapping a channel is user-initiated.
        c.play(channelID: "a")
        XCTAssertEqual(changes.last?.id, "a")
        XCTAssertEqual(changes.last?.userInitiated, true)

        // Swiping to the next channel is user-initiated.
        c.surf(.next)
        XCTAssertEqual(changes.last?.id, "b")
        XCTAssertEqual(changes.last?.userInitiated, true)

        // Auto-surf advancing on its timer is NOT user-initiated, so it must
        // not be recorded as the last-watched channel.
        c.startAutoSurf(interval: 10)
        clock.advance(by: 10)
        XCTAssertEqual(changes.last?.id, "c")
        XCTAssertEqual(changes.last?.userInitiated, false)
    }

    func test_stopPausesPlayerAndTearsDownTimers() {
        let player = MockPlayerService()
        let clock = ManualClock()
        let c = PlaybackController(player: player, clock: clock)
        c.setLineup(makeChannels())
        c.play(channelID: "a")
        c.startAutoSurf(interval: 10)
        c.startSleepTimer(seconds: 60)
        XCTAssertEqual(player.lastCommand, .play)

        c.stop()

        XCTAssertEqual(player.lastCommand, .pause)
        XCTAssertFalse(c.isAutoSurfActive)
        XCTAssertNil(c.autoSurfTimeRemaining)
        XCTAssertFalse(c.sleepTimerActive)

        // Timers are fully torn down: advancing the clock must not surf or pause again.
        player.simulate(state: .playing)
        clock.advance(by: 120)
        XCTAssertEqual(c.currentChannel?.id, "a")
    }

    func test_surfDoesNotReloadSingleChannelLineup() {
        let player = MockPlayerService()
        let clock = ManualClock()
        let c = PlaybackController(player: player, clock: clock)
        let singleChannel = Channel(id: "single", title: "Single", youTubeVideoID: "123", source: .curated, isLiveExpected: true)
        c.setLineup([singleChannel])
        c.play(channelID: "single")
        
        XCTAssertEqual(player.lastCommand, .play)
        
        // Change volume to set lastCommand to .volume
        player.setVolume(50)
        XCTAssertEqual(player.lastCommand, .volume)
        
        c.surf(.next)
        // Verify no reload or load was triggered
        XCTAssertEqual(player.lastCommand, .volume)
    }
}

@MainActor
final class SystemClockTests: XCTestCase {
    func test_systemClock_schedulesAndFires() async throws {
        let clock = SystemClock()
        let expectation = XCTestExpectation(description: "Timer fires")
        
        let token = clock.schedule(after: 0.05) {
            expectation.fulfill()
        }
        
        await fulfillment(of: [expectation], timeout: 0.5)
        _ = token // keep alive
    }
    
    func test_systemClock_cancelPreventsFiring() async throws {
        let clock = SystemClock()
        let expectation = XCTestExpectation(description: "Timer should not fire")
        expectation.isInverted = true
        
        let token = clock.schedule(after: 0.05) {
            expectation.fulfill()
        }
        token.cancel()
        
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        await fulfillment(of: [expectation], timeout: 0.1)
    }
}

