import Foundation
import Combine

@MainActor
final class MockPlayerService: PlayerService {
    private let stateSubject = CurrentValueSubject<PlayerState, Never>(.idle)
    private let eventSubject = PassthroughSubject<PlayerEvent, Never>()

    var statePublisher: AnyPublisher<PlayerState, Never> { stateSubject.eraseToAnyPublisher() }
    var eventPublisher: AnyPublisher<PlayerEvent, Never> { eventSubject.eraseToAnyPublisher() }

    private(set) var loadedChannel: Channel?
    private(set) var volume = 100
    private(set) var muted = false

    func load(channel: Channel) {
        loadedChannel = channel
        stateSubject.send(.loading)
    }
    func play() { stateSubject.send(.playing); eventSubject.send(.playbackStarted) }
    func pause() { stateSubject.send(.paused) }
    func setVolume(_ volume: Int) { self.volume = volume }
    func setMuted(_ muted: Bool) { self.muted = muted }

    // Test helpers to simulate player callbacks.
    func simulate(state: PlayerState) { stateSubject.send(state) }
    func simulate(event: PlayerEvent) { eventSubject.send(event) }
}
