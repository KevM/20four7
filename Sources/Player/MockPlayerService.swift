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

    // Test helpers to simulate player callbacks.
    func simulate(state: PlayerState) { stateSubject.send(state) }
    func simulate(event: PlayerEvent) { eventSubject.send(event) }
}
