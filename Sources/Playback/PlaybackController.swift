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
    @Published private(set) var isAutoSurfActive = false
    @Published private(set) var autoSurfTimeRemaining: TimeInterval?

    private let player: PlayerService
    private let clock: Clock
    private let channelStore: ChannelStore?
    private var lineup: [Channel] = []
    private var sleepToken: ClockToken?
    private var autoSurfInterval: TimeInterval = 0
    private var autoSurfToken: ClockToken?
    private var lastTickTime = Date(timeIntervalSince1970: 0)
    private var cancellables = Set<AnyCancellable>()

    /// Called when a channel starts playing, so callers can persist last-watched.
    var onChannelChanged: ((Channel, _ userInitiated: Bool) -> Void)?

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

    func play(channelID: String, startTime: TimeInterval = 0) {
        guard let channel = lineup.first(where: { $0.id == channelID }) else { return }
        isManuallyPaused = false
        if isAutoSurfActive {
            autoSurfTimeRemaining = autoSurfInterval
            lastTickTime = clock.now()
            scheduleNextAutoSurfTick()
        }
        start(channel, startTime: startTime, userInitiated: true)
    }

    func surf(_ direction: SurfDirection, userInitiated: Bool = true) {
        guard let current = currentChannel,
              let next = Surfer.channel(after: current.id, in: lineup, direction: direction) else {
            if isAutoSurfActive {
                stopAutoSurf()
            }
            return
        }
        if next.id == current.id {
            // Already playing the only channel in the lineup. Skip reload but reset timer.
            if isAutoSurfActive {
                autoSurfTimeRemaining = autoSurfInterval
                lastTickTime = clock.now()
                scheduleNextAutoSurfTick()
            }
            return
        }
        isManuallyPaused = false
        if isAutoSurfActive {
            autoSurfTimeRemaining = autoSurfInterval
            lastTickTime = clock.now()
            scheduleNextAutoSurfTick()
        }
        start(next, userInitiated: userInitiated)
    }

    func playFromUI() {
        isManuallyPaused = false
        player.play()
        if isAutoSurfActive {
            lastTickTime = clock.now()
            scheduleNextAutoSurfTick()
        }
    }

    func pauseFromUI() {
        isManuallyPaused = true
        player.pause()
        autoSurfToken?.cancel()
        autoSurfToken = nil
    }

    private func start(_ channel: Channel, startTime: TimeInterval = 0, userInitiated: Bool) {
        currentChannel = channel
        showsOfflineState = channelStore?.offlineChannelIDs.contains(channel.id) ?? false
        isCurrentlyLive = channel.isLiveExpected
        player.load(channel: channel, startTime: startTime)
        player.play()
        onChannelChanged?(channel, userInitiated)
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

    // MARK: Auto-Surf
    func startAutoSurf(interval: TimeInterval) {
        autoSurfInterval = interval
        autoSurfTimeRemaining = interval
        isAutoSurfActive = true
        lastTickTime = clock.now()
        scheduleNextAutoSurfTick()
    }

    func stopAutoSurf() {
        isAutoSurfActive = false
        autoSurfTimeRemaining = nil
        autoSurfToken?.cancel()
        autoSurfToken = nil
    }

    private func scheduleNextAutoSurfTick() {
        autoSurfToken?.cancel()
        guard isAutoSurfActive && !isManuallyPaused else { return }
        autoSurfToken = clock.schedule(after: 1) { [weak self] in
            self?.handleAutoSurfTick()
        }
    }

    private func handleAutoSurfTick() {
        guard isAutoSurfActive && !isManuallyPaused else { return }
        guard let remaining = autoSurfTimeRemaining else { return }
        let now = clock.now()
        let elapsed = now.timeIntervalSince(lastTickTime)
        if elapsed >= 1.0 {
            lastTickTime = now
            guard state == .playing else {
                // Player is loading or paused, keep rescheduling ticks but do not count down.
                scheduleNextAutoSurfTick()
                return
            }
            let nextRemaining = remaining - elapsed
            if nextRemaining <= 0 {
                surf(.next, userInitiated: false)
            } else {
                autoSurfTimeRemaining = nextRemaining
                scheduleNextAutoSurfTick()
            }
        } else {
            scheduleNextAutoSurfTick()
        }
    }
}
