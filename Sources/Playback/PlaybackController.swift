import Foundation
import Combine

/// App-level "what's playing now" state. Owns surf, sleep timer, audio-only,
/// and auto-resume bookkeeping. Drives a `PlayerService`.
@MainActor
final class PlaybackController: ObservableObject {
    @Published private(set) var currentChannel: Channel?
    @Published private(set) var state: PlayerState = .idle
    @Published private(set) var showsOfflineState = false
    @Published private(set) var sleepTimerActive = false

    private let player: PlayerService
    private let clock: Clock
    private var lineup: [Channel] = []
    private var sleepToken: ClockToken?
    private var cancellables = Set<AnyCancellable>()

    /// Called when a channel starts playing, so callers can persist last-watched.
    var onChannelChanged: ((Channel) -> Void)?

    init(player: PlayerService, clock: Clock) {
        self.player = player
        self.clock = clock
        bind()
    }

    private func bind() {
        player.statePublisher
            .sink { [weak self] in self?.state = $0 }
            .store(in: &cancellables)
        player.eventPublisher
            .sink { [weak self] event in
                switch event {
                case .streamOffline, .embeddingDisallowed:
                    self?.showsOfflineState = true
                case .playbackStarted:
                    self?.showsOfflineState = false
                case .ended:
                    break
                }
            }
            .store(in: &cancellables)
    }

    func setLineup(_ channels: [Channel]) { lineup = channels }

    func play(channelID: String) {
        guard let channel = lineup.first(where: { $0.id == channelID }) else { return }
        start(channel)
    }

    func surf(_ direction: SurfDirection) {
        guard let current = currentChannel,
              let next = Surfer.channel(after: current.id, in: lineup, direction: direction) else { return }
        start(next)
    }

    func playFromUI() { player.play() }
    func pauseFromUI() { player.pause() }

    private func start(_ channel: Channel) {
        currentChannel = channel
        showsOfflineState = false
        player.load(channel: channel)
        player.play()
        onChannelChanged?(channel)
    }

    // MARK: Sleep timer
    func startSleepTimer(seconds: TimeInterval) {
        sleepToken?.cancel()
        sleepTimerActive = true
        sleepToken = clock.schedule(after: seconds) { [weak self] in
            self?.player.pause()
            self?.sleepTimerActive = false
            self?.sleepToken = nil
        }
    }
    func cancelSleepTimer() {
        sleepToken?.cancel()
        sleepToken = nil
        sleepTimerActive = false
    }
}
