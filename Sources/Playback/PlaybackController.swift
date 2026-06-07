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
    /// Whether the user currently intends playback. Unlike `state`, this
    /// survives a background pause (where the player reports `.paused`), so on
    /// foreground we know whether to resume or assert a pause. Cleared by a
    /// manual pause, the sleep timer, or `stop()`.
    private var userIntendsPlayback = false
    /// Tracks foreground/background so a content-process crash behind a closed
    /// player or while backgrounded can't resurrect playback.
    private var isForeground = true
    /// The start offset the current channel was loaded with, replayed on
    /// content-process crash recovery.
    private var currentStartTime: TimeInterval = 0
    private var watchSegmentStart: Date?
    private var watchHeartbeatToken: ClockToken?
    private let watchHeartbeatInterval: TimeInterval = 60
    /// Segments shorter than this are discarded rather than persisted, so a
    /// brief playing→buffering→playing flap doesn't churn out tiny accruals
    /// (each of which would `save()` and re-stamp `lastPlayedDate`).
    private let minimumAccruedSeconds: TimeInterval = 1

    /// Called when a channel starts playing, so callers can persist last-watched.
    /// Invoked on the main actor, so the handler can touch `@MainActor` stores directly.
    var onChannelChanged: (@MainActor (Channel, _ userInitiated: Bool, _ isAutoSurf: Bool) -> Void)?

    /// Called when watch time accrues for a channel (on pause, channel change,
    /// stop, background, or the 60s heartbeat). Caller persists it. Invoked on
    /// the main actor, so the handler can touch `@MainActor` stores directly.
    var onWatchAccrued: (@MainActor (_ channelID: String, _ seconds: TimeInterval, _ date: Date) -> Void)?

    init(player: PlayerService, clock: Clock, channelStore: ChannelStore? = nil) {
        self.player = player
        self.clock = clock
        self.channelStore = channelStore
        bind()
    }

    private func bind() {
        player.statePublisher
            .sink { [weak self] state in
                guard let self else { return }
                let wasPlaying = self.state == .playing
                self.state = state
                if state == .playing {
                    self.beginWatchSegment()
                } else if wasPlaying {
                    self.flushWatchSegment()
                }
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
                case .contentProcessTerminated:
                    self?.handleContentProcessTermination()
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

    /// Tear down playback when the player UI is dismissed. Pauses the underlying
    /// player so audio doesn't keep playing behind the Guide, and stops the
    /// sleep and auto-surf timers. The shared player/web view outlives the
    /// `PlayerView`, so without this the YouTube iframe keeps playing.
    func stop() {
        isManuallyPaused = false
        userIntendsPlayback = false
        flushWatchSegment()
        player.pause()
        cancelSleepTimer()
        stopAutoSurf()
    }

    func playFromUI() {
        isManuallyPaused = false
        userIntendsPlayback = true
        player.play()
        if isAutoSurfActive {
            lastTickTime = clock.now()
            scheduleNextAutoSurfTick()
        }
    }

    func pauseFromUI() {
        isManuallyPaused = true
        userIntendsPlayback = false
        player.pause()
        autoSurfToken?.cancel()
        autoSurfToken = nil
    }

    /// Pause because the app is backgrounding. Unlike `pauseFromUI`, this does
    /// NOT set `isManuallyPaused` and does NOT clear `isAutoSurfActive`, so the
    /// user's intent and the surf mode survive a return to the foreground.
    func pauseForBackground() {
        isForeground = false
        flushWatchSegment()
        player.pause()
        autoSurfToken?.cancel()
        autoSurfToken = nil
    }

    /// Re-entering the foreground. Resume only when the user was actively
    /// watching and auto-resume is enabled; otherwise assert a pause to squash
    /// any playback the suspended WebKit media element resumed on its own while
    /// the app was backgrounded. Idempotent for transient `.inactive` overlays —
    /// callers should only invoke this after a real background pause.
    func enterForeground(autoResume: Bool) {
        isForeground = true
        if userIntendsPlayback && autoResume {
            playFromUI()
        } else {
            player.pause()
        }
    }

    /// The web content process crashed and the player service has reloaded its
    /// host page. Re-establish playback only when the user is actively watching
    /// in the foreground, so a crash behind a closed player or while
    /// backgrounded cannot resurrect playback.
    private func handleContentProcessTermination() {
        guard isForeground, userIntendsPlayback, let channel = currentChannel else { return }
        player.load(channel: channel, startTime: currentStartTime)
        player.play()
    }

    private func start(_ channel: Channel, startTime: TimeInterval = 0, userInitiated: Bool) {
        flushWatchSegment()
        userIntendsPlayback = true
        currentStartTime = startTime
        currentChannel = channel
        showsOfflineState = channelStore?.offlineChannelIDs.contains(channel.id) ?? false
        isCurrentlyLive = channel.isLiveExpected
        player.load(channel: channel, startTime: startTime)
        player.play()
        onChannelChanged?(channel, userInitiated, isAutoSurfActive)
    }

    // MARK: Sleep timer
    func startSleepTimer(seconds: TimeInterval) {
        sleepToken?.cancel()
        sleepTimerActive = true
        sleepToken = clock.schedule(after: seconds) { [weak self] in
            self?.isManuallyPaused = true
            self?.userIntendsPlayback = false
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

    // MARK: - Watch-time tracking

    /// Begin a watch segment if a channel is actively playing. Idempotent.
    private func beginWatchSegment() {
        guard currentChannel != nil, state == .playing, watchSegmentStart == nil else { return }
        watchSegmentStart = clock.now()
        scheduleWatchHeartbeat()
    }

    /// Flush the current segment's elapsed time to `onWatchAccrued` and end it.
    /// Idempotent: a no-op when no segment is open.
    private func flushWatchSegment() {
        watchHeartbeatToken?.cancel()
        watchHeartbeatToken = nil
        guard let start = watchSegmentStart, let channel = currentChannel else {
            watchSegmentStart = nil
            return
        }
        watchSegmentStart = nil
        let now = clock.now()
        let elapsed = now.timeIntervalSince(start)
        if elapsed >= minimumAccruedSeconds {
            onWatchAccrued?(channel.id, elapsed, now)
        }
    }

    private func scheduleWatchHeartbeat() {
        watchHeartbeatToken?.cancel()
        watchHeartbeatToken = clock.schedule(after: watchHeartbeatInterval) { [weak self] in
            self?.handleWatchHeartbeat()
        }
    }

    private func handleWatchHeartbeat() {
        // Flush accrued time, then reopen a fresh segment if still playing.
        flushWatchSegment()
        beginWatchSegment()
    }
}
