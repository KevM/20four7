import Foundation
import Combine
import WebKit

/// iOS playback via YouTube's IFrame Player API hosted in a WKWebView.
/// Exposes the shared `view` for SwiftUI to embed; all control goes through the
/// `PlayerService` API so the rest of the app never touches WebKit.
@MainActor
final class WebViewPlayerService: NSObject, PlayerService, WKScriptMessageHandler, WKNavigationDelegate {
    private(set) var webView: WKWebView!

    private let stateSubject = CurrentValueSubject<PlayerState, Never>(.idle)
    private let eventSubject = PassthroughSubject<PlayerEvent, Never>()
    var statePublisher: AnyPublisher<PlayerState, Never> { stateSubject.eraseToAnyPublisher() }
    var eventPublisher: AnyPublisher<PlayerEvent, Never> { eventSubject.eraseToAnyPublisher() }

    private var apiReady = false
    private var pendingVideoID: String?
    private var pendingLiveExpected = false
    private var pendingStartTime: TimeInterval = 0

    override init() {
        super.init()
        
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsAirPlayForMediaPlayback = false
        
        let hideChromeJS = """
        (function() {
            try {
                var css = '.ytp-chrome-top, .ytp-chrome-top-interface, [class*="share"], [class*="pause-overlay"], [class*="suggested"], [class*="expand"], [class*="watch-later"], [class*="cards"], [class*="teaser"], [class*="info-panel"], [aria-label*="share" i], [title*="share" i], [aria-label*="more videos" i], [title*="more videos" i] { opacity: 0 !important; pointer-events: none !important; }';
                
                // Hide all bottom control buttons except the logo, and hide progress bar / time display
                css += ' .ytp-chrome-bottom .ytp-button:not(.ytp-youtube-button), .ytp-progress-bar-container, .ytp-time-display { opacity: 0 !important; pointer-events: none !important; }';
                css += ' .ytp-chrome-bottom { background: none !important; }';

                var style = document.createElement('style');
                style.appendChild(document.createTextNode(css));
                document.documentElement.appendChild(style);
                
                var customStyleEl = null;
                window.addEventListener('message', function(e) {
                    if (e.data && e.data.type === 'setAspectCover') {
                        var cropX = e.data.cropX || 0;
                        var cropY = e.data.cropY || 0;
                        var safeArea = e.data.safeArea || { left: 0, right: 0, top: 0, bottom: 0 };
                        if (!customStyleEl) {
                            customStyleEl = document.createElement('style');
                            document.documentElement.appendChild(customStyleEl);
                        }
                        var leftOffset = 12 + cropX + safeArea.left;
                        var rightOffset = 12 + cropX + safeArea.right;
                        var bottomOffset = 12 + cropY + safeArea.bottom;
                        customStyleEl.textContent = '.ytp-chrome-bottom { left: ' + leftOffset + 'px !important; right: ' + rightOffset + 'px !important; bottom: ' + bottomOffset + 'px !important; width: auto !important; } .ytp-watermark, .ytp-logo, a.ytp-watermark { right: ' + rightOffset + 'px !important; bottom: ' + bottomOffset + 'px !important; }';
                    }
                });
                // Request initial aspect cover state from parent
                window.parent.postMessage({ type: 'requestAspectCover' }, '*');

                // Disable AirPlay media routing on all video elements to prevent stream casting failures and enforce mirroring
                function disableAirPlayOnVideos() {
                    try {
                        var videos = document.getElementsByTagName('video');
                        for (var i = 0; i < videos.length; i++) {
                            var video = videos[i];
                            if (video.getAttribute('x-webkit-airplay') !== 'deny') {
                                video.setAttribute('x-webkit-airplay', 'deny');
                                video.disableRemotePlayback = true;
                            }
                        }
                    } catch (e) {}
                }
                disableAirPlayOnVideos();
                var observer = new MutationObserver(disableAirPlayOnVideos);
                observer.observe(document.documentElement, { childList: true, subtree: true });
            } catch (e) {}
        })();
        """
        let userScript = WKUserScript(source: hideChromeJS, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        config.userContentController.addUserScript(userScript)
        config.userContentController.add(self, name: "player")
        
        self.webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
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
        webView.loadHTMLString(html, baseURL: URL(string: "https://20four7.fm.rodeo"))
    }

    // MARK: PlayerService
    func load(channel: Channel, startTime: TimeInterval) {
        stateSubject.send(.loading)
        if apiReady {
            loadVideo(id: channel.youTubeVideoID, liveExpected: channel.isLiveExpected, startTime: startTime)
        } else {
            pendingVideoID = channel.youTubeVideoID
            pendingLiveExpected = channel.isLiveExpected
            pendingStartTime = startTime
        }
    }

    /// Invokes the page's `loadVideo` with values bound as JavaScript arguments
    /// (never string-interpolated), so a channel's video id cannot break out of
    /// the call. `contentWorld: .page` matches the world where `player.html`
    /// defines `loadVideo`.
    private func loadVideo(id: String, liveExpected: Bool, startTime: TimeInterval) {
        Task { @MainActor in
            do {
                _ = try await webView.callAsyncJavaScript(
                    "loadVideo(videoId, isLiveExpected, false, false, startSeconds)",
                    arguments: ["videoId": id,
                                "isLiveExpected": liveExpected,
                                "startSeconds": startTime],
                    in: nil,
                    contentWorld: .page
                )
            } catch {
                #if DEBUG
                print("[WebViewPlayerService] loadVideo JS failed: \(error)")
                #endif
            }
        }
    }
    func play()  { evaluate("play()") }
    func pause() { evaluate("pause()") }
    func setVolume(_ volume: Int) { evaluate("setVolume(\(max(0, min(100, volume))))") }
    func setMuted(_ muted: Bool)  { evaluate("setMuted(\(muted))") }
    func setAspectCover(_ cover: Bool) { evaluate("setAspectCover(\(cover))") }

    func seekToLive() { evaluate("seekToLive()") }
    func setPlaybackRate(_ rate: Double) { evaluate("setPlaybackRate(\(rate))") }

    func liveDriftSeconds() async -> TimeInterval? {
        do {
            let result = try await webView.callAsyncJavaScript(
                "return liveDrift()", arguments: [:], in: nil, contentWorld: .page)
            if let n = result as? NSNumber { return n.doubleValue }
            return nil
        } catch {
            return nil
        }
    }

    func playbackRate() async -> Double {
        do {
            let result = try await webView.callAsyncJavaScript(
                "return getPlaybackRate()", arguments: [:], in: nil, contentWorld: .page)
            if let n = result as? NSNumber { return n.doubleValue }
            return 1.0
        } catch {
            return 1.0
        }
    }

    private func evaluate(_ js: String) { webView.evaluateJavaScript(js, completionHandler: nil) }

    // MARK: WKScriptMessageHandler
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "apiReady":
            apiReady = true
            if let pending = pendingVideoID {
                loadVideo(id: pending, liveExpected: pendingLiveExpected, startTime: pendingStartTime)
                pendingVideoID = nil
                pendingStartTime = 0
            }
        case "state":
            handlePlayerState(body["state"] as? Int ?? -1)
        case "error":
            handleError(code: body["code"] as? Int ?? -1)
        case "isLive":
            let isLive = body["isLive"] as? Bool ?? false
            eventSubject.send(.liveStatusDetected(isLive: isLive))
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

    // MARK: WKNavigationDelegate

    /// The WebContent process crashed (common under memory pressure, especially
    /// on iPad), leaving the shared web view blank with no way to recover —
    /// every later play attempt renders black until the app process is
    /// recreated. Reset state, reload the host page so the next load works, and
    /// notify the controller so it can re-establish the crashed video.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        apiReady = false
        pendingVideoID = nil
        pendingLiveExpected = false
        pendingStartTime = 0
        stateSubject.send(.loading)
        loadHostPage()
        eventSubject.send(.contentProcessTerminated)
    }
}
