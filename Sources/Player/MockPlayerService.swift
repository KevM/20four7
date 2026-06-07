import Foundation
import Combine

@MainActor
final class MockPlayerService: PlayerService {
    private let stateSubject = CurrentValueSubject<PlayerState, Never>(.idle)
    private let eventSubject = PassthroughSubject<PlayerEvent, Never>()

    var statePublisher: AnyPublisher<PlayerState, Never> { stateSubject.eraseToAnyPublisher() }
    var eventPublisher: AnyPublisher<PlayerEvent, Never> { eventSubject.eraseToAnyPublisher() }

    private(set) var loadedChannel: Channel?
    private(set) var loadedStartTime: TimeInterval?
    private(set) var loadCount = 0
    private(set) var volume = 100
    private(set) var muted = false
    private(set) var seekToLiveCount = 0
    private(set) var rateHistory: [Double] = []
    private(set) var currentRate: Double = 1.0
    /// Test inputs: the drift `liveDriftSeconds()` returns, and the rate
    /// `playbackRate()` reports back (set to 1.0 to simulate a clamped rate).
    var driftToReturn: TimeInterval?
    var rateToReturn: Double?

    enum Command: Equatable { case load, play, pause, volume, mute }
    private(set) var lastCommand: Command?

    func load(channel: Channel, startTime: TimeInterval) {
        lastCommand = .load
        loadCount += 1
        loadedChannel = channel
        loadedStartTime = startTime
        stateSubject.send(.loading)
    }
    func play() { lastCommand = .play; stateSubject.send(.playing) }
    func pause() { lastCommand = .pause; stateSubject.send(.paused) }
    func setVolume(_ volume: Int) { lastCommand = .volume; self.volume = volume }
    func setMuted(_ muted: Bool) { lastCommand = .mute; self.muted = muted }
    func seekToLive() { seekToLiveCount += 1 }
    func setPlaybackRate(_ rate: Double) { currentRate = rate; rateHistory.append(rate) }
    func liveDriftSeconds() async -> TimeInterval? { driftToReturn }
    func playbackRate() async -> Double { rateToReturn ?? currentRate }

    // Test helpers to simulate player callbacks.
    func simulate(state: PlayerState) { stateSubject.send(state) }
    func simulate(event: PlayerEvent) { eventSubject.send(event) }
}
