import Foundation
import Combine
import WebKit

/// iOS playback via YouTube's IFrame Player API hosted in a WKWebView.
/// Exposes the shared `view` for SwiftUI to embed; all control goes through the
/// `PlayerService` API so the rest of the app never touches WebKit.
@MainActor
final class WebViewPlayerService: NSObject, PlayerService, WKScriptMessageHandler {
    let webView: WKWebView

    private let stateSubject = CurrentValueSubject<PlayerState, Never>(.idle)
    private let eventSubject = PassthroughSubject<PlayerEvent, Never>()
    var statePublisher: AnyPublisher<PlayerState, Never> { stateSubject.eraseToAnyPublisher() }
    var eventPublisher: AnyPublisher<PlayerEvent, Never> { eventSubject.eraseToAnyPublisher() }

    private var apiReady = false
    private var pendingVideoID: String?

    override init() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        self.webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        config.userContentController.add(self, name: "player")
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        loadHostPage()
    }

    private func loadHostPage() {
        guard let url = Bundle.main.url(forResource: "player", withExtension: "html"),
              let html = try? String(contentsOf: url, encoding: .utf8) else {
            stateSubject.send(.error(reason: .generic("player.html missing")))
            return
        }
        // Serve the page from an https origin. Loading from a file:// URL gives the
        // YouTube IFrame player a null/file origin, which it rejects with
        // "Video player configuration error" (error 153).
        webView.loadHTMLString(html, baseURL: URL(string: "https://televista.fm.rodeo"))
    }

    // MARK: PlayerService
    func load(channel: Channel) {
        stateSubject.send(.loading)
        if apiReady {
            evaluate("loadVideo('\(channel.youTubeVideoID)')")
        } else {
            pendingVideoID = channel.youTubeVideoID
        }
    }
    func play()  { evaluate("play()") }
    func pause() { evaluate("pause()") }
    func setVolume(_ volume: Int) { evaluate("setVolume(\(max(0, min(100, volume))))") }
    func setMuted(_ muted: Bool)  { evaluate("setMuted(\(muted))") }

    private func evaluate(_ js: String) { webView.evaluateJavaScript(js, completionHandler: nil) }

    // MARK: WKScriptMessageHandler
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "apiReady":
            apiReady = true
            if let pending = pendingVideoID { evaluate("loadVideo('\(pending)')"); pendingVideoID = nil }
        case "state":
            handlePlayerState(body["state"] as? Int ?? -1)
        case "error":
            handleError(code: body["code"] as? Int ?? -1)
        default:
            break
        }
    }

    /// YouTube player states: -1 unstarted, 0 ended, 1 playing, 2 paused, 3 buffering, 5 cued.
    private func handlePlayerState(_ raw: Int) {
        switch raw {
        case 1: stateSubject.send(.playing); eventSubject.send(.playbackStarted)
        case 2: stateSubject.send(.paused)
        case 3: stateSubject.send(.loading)
        case 0: stateSubject.send(.ended); eventSubject.send(.ended)
        default: break
        }
    }

    /// YouTube error codes: 101/150 embedding disallowed; 2 invalid; 100 not found; 5 html5.
    private func handleError(code: Int) {
        switch code {
        case 101, 150:
            stateSubject.send(.error(reason: .embeddingDisallowed))
            eventSubject.send(.embeddingDisallowed)
        case 100:
            stateSubject.send(.error(reason: .streamOffline))
            eventSubject.send(.streamOffline)
        default:
            stateSubject.send(.error(reason: .generic("YT error \(code)")))
        }
    }
}
