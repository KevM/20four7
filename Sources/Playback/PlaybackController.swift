import Foundation
import Combine
import AVFoundation

/// App-level "what's playing now" state. Owns surf, sleep timer, audio-only,
/// and auto-resume bookkeeping. Drives a `PlayerService`.
@MainActor
final class PlaybackController: ObservableObject {
    @Published private(set) var currentChannel: Channel?
    @Published private(set) var state: PlayerState = .idle
    @Published private(set) var showsOfflineState = false
    @Published private(set) var sleepTimerActive = false
    @Published private(set) var isManuallyPaused = false

    private let player: PlayerService
    private let clock: Clock
    private var lineup: [Channel] = []
    private var sleepToken: ClockToken?
    private var cancellables = Set<AnyCancellable>()
    private var silentPlayer: AVAudioPlayer?

    /// Called when a channel starts playing, so callers can persist last-watched.
    var onChannelChanged: ((Channel) -> Void)?

    init(player: PlayerService, clock: Clock) {
        self.player = player
        self.clock = clock
        setupSilentPlayer()
        bind()
    }

    private func bind() {
        player.statePublisher
            .sink { [weak self] state in
                self?.state = state
                if state == .playing || state == .loading {
                    self?.silentPlayer?.play()
                } else {
                    self?.silentPlayer?.pause()
                }
            }
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

    private func setupSilentPlayer() {
        let sampleRate: Int32 = 8000
        let durationSeconds: Int32 = 1
        let numChannels: Int16 = 1
        let bitsPerSample: Int16 = 16
        
        let subchunk2Size = sampleRate * durationSeconds * Int32(numChannels) * Int32(bitsPerSample / 8)
        let chunkSize = 36 + subchunk2Size
        
        var header = Data()
        header.append("RIFF".data(using: .utf8)!)
        header.append(withUnsafeBytes(of: chunkSize.littleEndian) { Data($0) })
        header.append("WAVE".data(using: .utf8)!)
        header.append("fmt ".data(using: .utf8)!)
        let subchunk1Size: Int32 = 16
        header.append(withUnsafeBytes(of: subchunk1Size.littleEndian) { Data($0) })
        let audioFormat: Int16 = 1
        header.append(withUnsafeBytes(of: audioFormat.littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: numChannels.littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: sampleRate.littleEndian) { Data($0) })
        let byteRate = sampleRate * Int32(numChannels) * Int32(bitsPerSample / 8)
        header.append(withUnsafeBytes(of: byteRate.littleEndian) { Data($0) })
        let blockAlign = numChannels * (bitsPerSample / 8)
        header.append(withUnsafeBytes(of: blockAlign.littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: bitsPerSample.littleEndian) { Data($0) })
        header.append("data".data(using: .utf8)!)
        header.append(withUnsafeBytes(of: subchunk2Size.littleEndian) { Data($0) })
        header.append(Data(repeating: 0, count: Int(subchunk2Size)))
        
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let silentURL = cacheDir.appendingPathComponent("silence.wav")
        try? header.write(to: silentURL)
        
        self.silentPlayer = try? AVAudioPlayer(contentsOf: silentURL)
        self.silentPlayer?.numberOfLoops = -1
        self.silentPlayer?.prepareToPlay()
    }
}
