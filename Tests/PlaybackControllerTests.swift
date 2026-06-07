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

        var changes: [(id: String, userInitiated: Bool, isAutoSurf: Bool)] = []
        c.onChannelChanged = { channel, userInitiated, isAutoSurf in
            changes.append((channel.id, userInitiated, isAutoSurf))
        }

        // Tapping a channel: user-initiated, not auto-surf.
        c.play(channelID: "a")
        XCTAssertEqual(changes.last?.id, "a")
        XCTAssertEqual(changes.last?.userInitiated, true)
        XCTAssertEqual(changes.last?.isAutoSurf, false)

        // Swiping to the next channel: user-initiated, not auto-surf.
        c.surf(.next)
        XCTAssertEqual(changes.last?.id, "b")
        XCTAssertEqual(changes.last?.userInitiated, true)
        XCTAssertEqual(changes.last?.isAutoSurf, false)

        // Auto-surf timer advance: NOT user-initiated, IS auto-surf.
        c.startAutoSurf(interval: 10)
        clock.advance(by: 10)
        XCTAssertEqual(changes.last?.id, "c")
        XCTAssertEqual(changes.last?.userInitiated, false)
        XCTAssertEqual(changes.last?.isAutoSurf, true)
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

    func test_pauseForBackgroundKeepsIntentAndSurfMode() {
        let player = MockPlayerService()
        let clock = ManualClock()
        let c = PlaybackController(player: player, clock: clock)
        c.setLineup(makeChannels())
        c.play(channelID: "a")
        c.startAutoSurf(interval: 10)
        XCTAssertTrue(c.isAutoSurfActive)
        XCTAssertFalse(c.isManuallyPaused)

        c.pauseForBackground()

        XCTAssertEqual(player.lastCommand, .pause)
        XCTAssertFalse(c.isManuallyPaused)   // not recorded as a manual pause
        XCTAssertTrue(c.isAutoSurfActive)    // surf mode preserved across background

        // The auto-surf countdown is suspended while backgrounded.
        let remainingBefore = c.autoSurfTimeRemaining
        clock.advance(by: 5)
        XCTAssertEqual(c.autoSurfTimeRemaining, remainingBefore)
    }

    // MARK: - Content-process crash recovery & foreground state assertion

    func test_contentProcessTerminationRestoresPlaybackWhileWatching() {
        let player = MockPlayerService()
        let c = PlaybackController(player: player, clock: ManualClock())
        c.setLineup(makeChannels())
        c.play(channelID: "a", startTime: 42)
        player.simulate(state: .playing)

        let loadsBefore = player.loadCount
        player.simulate(event: .contentProcessTerminated)

        // The crashed video is reloaded (at its original start) and resumed.
        XCTAssertEqual(player.loadCount, loadsBefore + 1)
        XCTAssertEqual(player.loadedChannel?.id, "a")
        XCTAssertEqual(player.loadedStartTime, 42)
        XCTAssertEqual(player.lastCommand, .play)
    }

    func test_contentProcessTerminationDoesNotResurrectAfterStop() {
        let player = MockPlayerService()
        let c = PlaybackController(player: player, clock: ManualClock())
        c.setLineup(makeChannels())
        c.play(channelID: "a")
        player.simulate(state: .playing)
        c.stop()                       // player closed -> no playback intent

        let loadsBefore = player.loadCount
        player.simulate(event: .contentProcessTerminated)

        XCTAssertEqual(player.loadCount, loadsBefore)   // no ghost playback
    }

    func test_contentProcessTerminationDoesNotResurrectWhileBackgrounded() {
        let player = MockPlayerService()
        let c = PlaybackController(player: player, clock: ManualClock())
        c.setLineup(makeChannels())
        c.play(channelID: "a")
        player.simulate(state: .playing)
        c.pauseForBackground()         // a crash while backgrounded must stay silent

        let loadsBefore = player.loadCount
        player.simulate(event: .contentProcessTerminated)

        XCTAssertEqual(player.loadCount, loadsBefore)
    }

    func test_enterForegroundAssertsPauseWhenNotResuming() {
        let player = MockPlayerService()
        let c = PlaybackController(player: player, clock: ManualClock())
        c.setLineup(makeChannels())
        c.play(channelID: "a")
        player.simulate(state: .playing)
        c.pauseForBackground()
        // Simulate WebKit resuming the suspended iframe on its own.
        player.simulate(state: .playing)

        c.enterForeground(autoResume: false)

        XCTAssertEqual(player.lastCommand, .pause)   // we squash the self-resume
    }

    func test_enterForegroundResumesWhenAutoResumeAndWatching() {
        let player = MockPlayerService()
        let c = PlaybackController(player: player, clock: ManualClock())
        c.setLineup(makeChannels())
        c.play(channelID: "a")
        player.simulate(state: .playing)
        c.pauseForBackground()

        c.enterForeground(autoResume: true)

        XCTAssertEqual(player.lastCommand, .play)
    }

    func test_enterForegroundDoesNotResumeAfterManualPause() {
        let player = MockPlayerService()
        let c = PlaybackController(player: player, clock: ManualClock())
        c.setLineup(makeChannels())
        c.play(channelID: "a")
        c.pauseFromUI()                // user paused -> no intent to resume
        c.pauseForBackground()

        c.enterForeground(autoResume: true)

        XCTAssertEqual(player.lastCommand, .pause)   // stays paused
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

    func test_watchAccruesOnPause() {
        let player = MockPlayerService()
        let clock = ManualClock()
        let c = PlaybackController(player: player, clock: clock)
        var accrued: [(String, TimeInterval)] = []
        c.onWatchAccrued = { id, secs, _ in accrued.append((id, secs)) }
        c.setLineup(makeChannels())
        c.play(channelID: "a")          // -> .playing, segment starts at t=0
        clock.advance(by: 30)
        c.pauseFromUI()                 // -> .paused, flush 30s for "a"
        XCTAssertEqual(accrued.count, 1)
        XCTAssertEqual(accrued.first?.0, "a")
        XCTAssertEqual(accrued.first?.1 ?? 0, 30, accuracy: 0.0001)
    }

    func test_watchAccruesToOldChannelOnSurf() {
        let player = MockPlayerService()
        let clock = ManualClock()
        let c = PlaybackController(player: player, clock: clock)
        var accrued: [(String, TimeInterval)] = []
        c.onWatchAccrued = { id, secs, _ in accrued.append((id, secs)) }
        c.setLineup(makeChannels())
        c.play(channelID: "a")
        clock.advance(by: 20)
        c.surf(.next)                   // flush 20s to "a" before switching to "b"
        XCTAssertEqual(accrued.first?.0, "a")
        XCTAssertEqual(accrued.first?.1 ?? 0, 20, accuracy: 0.0001)
    }

    func test_watchHeartbeatFlushesDuringLongSession() {
        let player = MockPlayerService()
        let clock = ManualClock()
        let c = PlaybackController(player: player, clock: clock)
        var accrued: [(String, TimeInterval)] = []
        c.onWatchAccrued = { id, secs, _ in accrued.append((id, secs)) }
        c.setLineup(makeChannels())
        c.play(channelID: "a")          // segment + heartbeat scheduled at t=60
        clock.advance(by: 60)           // heartbeat #1 -> flush 60s, reschedule
        clock.advance(by: 60)           // heartbeat #2 -> flush 60s
        XCTAssertEqual(accrued.count, 2)
        XCTAssertEqual(accrued.allSatisfy { $0.0 == "a" }, true)
        XCTAssertEqual(accrued.reduce(0) { $0 + $1.1 }, 120, accuracy: 0.0001)
    }

    func test_noWatchAccruesWhilePaused() {
        let player = MockPlayerService()
        let clock = ManualClock()
        let c = PlaybackController(player: player, clock: clock)
        var total: TimeInterval = 0
        c.onWatchAccrued = { _, secs, _ in total += secs }
        c.setLineup(makeChannels())
        c.play(channelID: "a")
        clock.advance(by: 10)
        c.pauseFromUI()                 // flush 10s
        clock.advance(by: 100)          // paused: nothing accrues
        XCTAssertEqual(total, 10, accuracy: 0.0001)
    }

    func test_subSecondWatchIsDiscarded() {
        let player = MockPlayerService()
        let clock = ManualClock()
        let c = PlaybackController(player: player, clock: clock)
        var accrued: [(String, TimeInterval)] = []
        c.onWatchAccrued = { id, secs, _ in accrued.append((id, secs)) }
        c.setLineup(makeChannels())
        c.play(channelID: "a")
        clock.advance(by: 0.5)          // a brief buffering flap, < 1s
        c.pauseFromUI()                 // sub-second segment is dropped, not persisted
        XCTAssertTrue(accrued.isEmpty)
    }

    // MARK: - Behind-live detection

    func test_pausingLiveStreamMarksBehind() {
        let player = MockPlayerService()
        let c = PlaybackController(player: player, clock: ManualClock())
        c.setLineup(makeChannels())          // makeChannels() are isLiveExpected: true
        c.play(channelID: "a")
        player.simulate(state: .playing)
        XCTAssertFalse(c.isBehindLive)

        c.pauseFromUI()
        XCTAssertTrue(c.isBehindLive)
    }

    func test_pausingNonLiveStreamDoesNotMarkBehind() {
        let player = MockPlayerService()
        let c = PlaybackController(player: player, clock: ManualClock())
        let vod = Channel(id: "vod", title: "VOD", youTubeVideoID: "v", source: .curated, isLiveExpected: false)
        c.setLineup([vod])
        c.play(channelID: "vod")
        player.simulate(state: .playing)

        c.pauseFromUI()
        XCTAssertFalse(c.isBehindLive)
    }

    func test_backgroundPauseMarksLiveStreamBehind() {
        let player = MockPlayerService()
        let c = PlaybackController(player: player, clock: ManualClock())
        c.setLineup(makeChannels())
        c.play(channelID: "a")
        player.simulate(state: .playing)

        c.pauseForBackground()
        XCTAssertTrue(c.isBehindLive)
    }

    func test_surfingToAnotherChannelClearsBehind() {
        let player = MockPlayerService()
        let c = PlaybackController(player: player, clock: ManualClock())
        c.setLineup(makeChannels())
        c.play(channelID: "a")
        player.simulate(state: .playing)
        c.pauseFromUI()
        XCTAssertTrue(c.isBehindLive)

        c.surf(.next)                        // fresh load is at the live edge
        XCTAssertFalse(c.isBehindLive)
    }

    func test_liveStatusFalseClearsBehind() {
        let player = MockPlayerService()
        let c = PlaybackController(player: player, clock: ManualClock())
        c.setLineup(makeChannels())
        c.play(channelID: "a")
        player.simulate(state: .playing)
        c.pauseFromUI()
        XCTAssertTrue(c.isBehindLive)

        player.simulate(event: .liveStatusDetected(isLive: false))
        XCTAssertFalse(c.isBehindLive)
    }

    // MARK: - Go Live catch-up

    /// Pauses a freshly-played live channel so `isBehindLive` is true, returning
    /// the wired controller, player, and clock.
    private func behindLiveSetup() -> (PlaybackController, MockPlayerService, ManualClock) {
        let player = MockPlayerService()
        let clock = ManualClock()
        let c = PlaybackController(player: player, clock: clock)
        c.setLineup(makeChannels())
        c.play(channelID: "a")
        player.simulate(state: .playing)
        c.pauseFromUI()
        return (c, player, clock)
    }

    func test_goLiveRampsWhenCloseToLive() async {
        let (c, player, clock) = behindLiveSetup()
        player.driftToReturn = 10            // 10s behind, within the 30s window

        await c.goLive()

        XCTAssertEqual(player.rateHistory.last, 2.0)   // ramped to 2×
        XCTAssertEqual(player.seekToLiveCount, 0)      // ramp, not a hard seek
        XCTAssertFalse(c.isBehindLive)                 // committed to live

        // Catch-up completes after 10 / (2 − 1) = 10s, restoring 1×.
        clock.advance(by: 10)
        XCTAssertEqual(player.rateHistory.last, 1.0)
    }

    func test_goLiveSeeksWhenFarBehind() async {
        let (c, player, _) = behindLiveSetup()
        player.driftToReturn = 120           // beyond the 30s window

        await c.goLive()

        XCTAssertEqual(player.seekToLiveCount, 1)
        XCTAssertTrue(player.rateHistory.isEmpty)      // never touched the rate
        XCTAssertFalse(c.isBehindLive)
    }

    func test_goLiveFallsBackToSeekWhenRateClamped() async {
        let (c, player, clock) = behindLiveSetup()
        player.driftToReturn = 10
        player.rateToReturn = 1.0            // YouTube refuses the rate change

        await c.goLive()

        XCTAssertEqual(player.seekToLiveCount, 1)      // fell back to a hard seek
        XCTAssertEqual(player.rateHistory.last, 1.0)   // attempt was undone to 1×
        XCTAssertFalse(c.isBehindLive)

        clock.advance(by: 60)                          // no ramp was scheduled
        XCTAssertEqual(player.rateHistory.last, 1.0)
    }

    func test_goLiveIsNoOpWhenNotBehind() async {
        let player = MockPlayerService()
        let c = PlaybackController(player: player, clock: ManualClock())
        c.setLineup(makeChannels())
        c.play(channelID: "a")
        player.simulate(state: .playing)     // at the edge, not behind
        player.driftToReturn = 10

        await c.goLive()

        XCTAssertEqual(player.seekToLiveCount, 0)
        XCTAssertTrue(player.rateHistory.isEmpty)
    }

    func test_manualPauseDuringRampRestoresRateAndClearsIntent() async {
        let (c, player, clock) = behindLiveSetup()
        player.driftToReturn = 10
        await c.goLive()
        XCTAssertEqual(player.rateHistory.last, 2.0)

        c.pauseFromUI()                      // deliberate exit
        XCTAssertEqual(player.rateHistory.last, 1.0)   // rate restored immediately

        clock.advance(by: 30)                          // ramp token cancelled
        XCTAssertEqual(player.rateHistory.last, 1.0)

        c.playFromUI()                       // deliberate exit cleared intent
        XCTAssertEqual(player.seekToLiveCount, 0)
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

