import XCTest
import Combine
@testable import Televista

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
}
