import Foundation
import Combine

/// App-level "what's playing now" state. Owns surf, sleep timer, audio-only,
/// and auto-resume bookkeeping. Drives a `PlayerService`.
@MainActor
final class PlaybackController: ObservableObject {
    @Published private(set) var currentChannel: Channel?
    @Published private(set) var state: PlayerState = .idle
    @Published private(set) var showsOfflineState = false
    @Published private(set) var isCurrentlyLive = false
    @Published private(set) var sleepTimerActive = false
    @Published private(set) var isManuallyPaused = false

    private let player: PlayerService
    private let clock: Clock
    private let channelStore: ChannelStore?
    private var lineup: [Channel] = []
    private var sleepToken: ClockToken?
    private var cancellables = Set<AnyCancellable>()

    /// Called when a channel starts playing, so callers can persist last-watched.
    var onChannelChanged: ((Channel) -> Void)?

    init(player: PlayerService, clock: Clock, channelStore: ChannelStore? = nil) {
        self.player = player
        self.clock = clock
        self.channelStore = channelStore
        bind()
    }

    private func bind() {
        player.statePublisher
            .sink { [weak self] state in
                self?.state = state
            }
            .store(in: &cancellables)
        player.eventPublisher
            .sink { [weak self] event in
                switch event {
                case .streamOffline, .embeddingDisallowed:
                    self?.showsOfflineState = true
                    if let channel = self?.currentChannel {
                        self?.channelStore?.markChannelOffline(id: channel.id)
                    }
                case .playbackStarted:
                    if let channel = self?.currentChannel {
                        self?.channelStore?.markChannelOnline(id: channel.id)
                    }
                    self?.showsOfflineState = false
                case .liveStatusDetected(let isLive):
                    self?.isCurrentlyLive = isLive
                    if let channel = self?.currentChannel {
                        self?.channelStore?.updateLiveStatus(channelID: channel.id, isLive: isLive)
                    }
                case .ended:
                    break
                }
            }
            .store(in: &cancellables)
    }

    func setLineup(_ channels: [Channel]) { lineup = channels }

    func play(channelID: String) {
        guard let channel = lineup.first(where: { $0.id == channelID }) else { return }
        isManuallyPaused = false
        start(channel)
    }

    func surf(_ direction: SurfDirection) {
        guard let current = currentChannel,
              let next = Surfer.channel(after: current.id, in: lineup, direction: direction) else { return }
        isManuallyPaused = false
        start(next)
    }

    func playFromUI() {
        isManuallyPaused = false
        player.play()
    }

    func pauseFromUI() {
        isManuallyPaused = true
        player.pause()
    }

    private func start(_ channel: Channel) {
        channelStore?.stopBackgroundScan()
        currentChannel = channel
        showsOfflineState = channelStore?.offlineChannelIDs.contains(channel.id) ?? false
        isCurrentlyLive = channel.isLiveExpected
        player.load(channel: channel)
        player.play()
        onChannelChanged?(channel)
    }

    // MARK: Sleep timer
    func startSleepTimer(seconds: TimeInterval) {
        sleepToken?.cancel()
        sleepTimerActive = true
        sleepToken = clock.schedule(after: seconds) { [weak self] in
            self?.isManuallyPaused = true
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
