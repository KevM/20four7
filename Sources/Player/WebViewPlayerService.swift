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
        config.allowsPictureInPictureMediaPlayback = true
        config.allowsAirPlayForMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        
        let overrideJS = """
        (function() {
            try {
                if (navigator.audioSession) {
                    navigator.audioSession.type = 'playback';
                }
                
                var isUserPaused = false;
                window.addEventListener('message', function(event) {
                    if (event.data && event.data.type === 'user-pause') {
                        isUserPaused = true;
                    } else if (event.data && event.data.type === 'user-play') {
                        isUserPaused = false;
                    }
                });

                Object.defineProperty(document, 'visibilityState', { value: 'visible', writable: false });
                Object.defineProperty(document, 'hidden', { value: false, writable: false });
                Object.defineProperty(document, 'hasFocus', { value: function() { return true; }, writable: false });
                
                var originalAdd = EventTarget.prototype.addEventListener;
                EventTarget.prototype.addEventListener = function(type, listener, options) {
                    if (type === 'visibilitychange' || 
                        type === 'webkitvisibilitychange' || 
                        type === 'pagehide' || 
                        type === 'blur') {
                        return;
                    }
                    originalAdd.call(this, type, listener, options);
                };
                
                var blockProperties = [document, window, Document.prototype, Window.prototype];
                var blockEvents = ['onvisibilitychange', 'onwebkitvisibilitychange', 'onpagehide', 'onblur'];
                for (var i = 0; i < blockProperties.length; i++) {
                    var target = blockProperties[i];
                    for (var j = 0; j < blockEvents.length; j++) {
                        var event = blockEvents[j];
                        try {
                            Object.defineProperty(target, event, {
                                get: function() { return null; },
                                set: function(val) {},
                                configurable: true
                            });
                        } catch (e) {}
                    }
                }

                // Override HTMLMediaElement.prototype.pause
                var originalPause = HTMLMediaElement.prototype.pause;
                HTMLMediaElement.prototype.pause = function() {
                    if (isUserPaused) {
                        return originalPause.apply(this, arguments);
                    }
                    console.log('Prevented HTMLMediaElement pause');
                    return Promise.resolve();
                };

                // Helper to attach play-on-pause listener to media elements
                var originalPlay = HTMLMediaElement.prototype.play;
                function setupMediaElement(element) {
                    if (element.__setupDone) return;
                    element.__setupDone = true;
                    element.addEventListener('pause', function(event) {
                        if (!isUserPaused) {
                            console.log('Auto-resuming media element');
                            originalPlay.apply(element).catch(function(err) {
                                console.error('Error auto-resuming media:', err);
                            });
                        }
                    });
                }

                // Intercept createElement to setup dynamically created media elements
                var originalCreateElement = document.createElement;
                document.createElement = function(tagName) {
                    var element = originalCreateElement.apply(this, arguments);
                    var tag = tagName.toLowerCase();
                    if (tag === 'video' || tag === 'audio') {
                        setupMediaElement(element);
                    }
                    return element;
                };

                // Watch DOM to hook onto any parsed/injected media elements
                var observer = new MutationObserver(function(mutations) {
                    for (var i = 0; i < mutations.length; i++) {
                        var mutation = mutations[i];
                        for (var j = 0; j < mutation.addedNodes.length; j++) {
                            var node = mutation.addedNodes[j];
                            if (node.nodeType === Node.ELEMENT_NODE) {
                                var tag = node.tagName.toLowerCase();
                                if (tag === 'video' || tag === 'audio') {
                                    setupMediaElement(node);
                                }
                                var childMedia = node.querySelectorAll('video, audio');
                                for (var k = 0; k < childMedia.length; k++) {
                                    setupMediaElement(childMedia[k]);
                                }
                            }
                        }
                    }
                });
                observer.observe(document.documentElement, { childList: true, subtree: true });

            } catch (e) {}
        })();
        """
        let userScript = WKUserScript(source: overrideJS, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        config.userContentController.addUserScript(userScript)
        
        self.webView = WKWebView(frame: .zero, configuration: config)
        self.webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15"
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
        webView.loadHTMLString(html, baseURL: URL(string: "https://20four7.fm.rodeo"))
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
    func setAspectCover(_ cover: Bool) { evaluate("setAspectCover(\(cover))") }

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
