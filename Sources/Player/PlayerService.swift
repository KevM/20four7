import Foundation
import Combine

enum PlayerState: Equatable, Sendable {
    case idle
    case loading
    case playing
    case paused
    case ended
    case error(reason: PlayerErrorReason)
}

enum PlayerErrorReason: Equatable, Sendable {
    case embeddingDisallowed   // YouTube error 101 / 150
    case streamOffline
    case generic(String)
}

enum PlayerEvent: Equatable, Sendable {
    case playbackStarted
    case ended
    case embeddingDisallowed
    case streamOffline
    case liveStatusDetected(isLive: Bool)
    /// The underlying web content process crashed. The service has reloaded its
    /// host page; the controller decides whether to re-establish playback.
    case contentProcessTerminated
}

/// Platform-agnostic playback boundary. The iOS implementation wraps the YouTube
/// IFrame Player; tests use `MockPlayerService`; a future tvOS impl conforms here.
@MainActor
protocol PlayerService: AnyObject {
    var statePublisher: AnyPublisher<PlayerState, Never> { get }
    var eventPublisher: AnyPublisher<PlayerEvent, Never> { get }

    func load(channel: Channel, startTime: TimeInterval)
    func play()
    func pause()
    func setVolume(_ volume: Int)   // 0...100
    func setMuted(_ muted: Bool)

    /// Seek to the live edge of a live stream and play.
    func seekToLive()
    /// Set the playback speed multiplier (1.0 == normal).
    func setPlaybackRate(_ rate: Double)
    /// One-shot seconds-behind-live (`getDuration() − getCurrentTime()`).
    /// `nil` when the video is not live or the value is unavailable.
    func liveDriftSeconds() async -> TimeInterval?
    /// The playback rate the player actually applied (used to detect a rate the
    /// platform clamped or refused).
    func playbackRate() async -> Double
}

extension PlayerService {
    func load(channel: Channel) {
        load(channel: channel, startTime: 0)
    }
}
