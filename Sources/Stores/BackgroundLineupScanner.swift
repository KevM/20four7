import Foundation
import WebKit
import Network
import os

private let logger = Logger(subsystem: "fm.rodeo.20four7", category: "BackgroundLineupScanner")

@MainActor
final class BackgroundLineupScanner: NSObject, WKScriptMessageHandler {
    private weak var store: ChannelStore?
    private(set) var webView: WKWebView!
    private(set) var queue: [Channel] = []
    private(set) var currentChannel: Channel?
    private(set) var isScanning = false
    private var apiReady = false
    
    private let pathMonitor = NWPathMonitor()
    private var isExpensiveConnection = false
    
    private let defaults: UserDefaults
    private let lastScanKey = "com.televista.lastScanTime"
    private let scanCooldown: TimeInterval = 6 * 3600 // 6 hours
    private var timeoutTask: Task<Void, Never>?
    private var delayTask: Task<Void, Never>?

    init(store: ChannelStore, defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
        super.init()
        
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        
        let muteJS = """
        (function() {
            var muteVideos = function() {
                var videos = document.getElementsByTagName('video');
                for (var i = 0; i < videos.length; i++) {
                    videos[i].volume = 0;
                    videos[i].muted = true;
                }
            };
            muteVideos();
            var observer = new MutationObserver(muteVideos);
            observer.observe(document.documentElement, { childList: true, subtree: true });
        })();
        """
        let userScript = WKUserScript(source: muteJS, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        config.userContentController.addUserScript(userScript)
        config.userContentController.add(self, name: "player")
        
        self.webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 200, height: 200), configuration: config)
        setupNetworkMonitor()
    }
    
    deinit {
        pathMonitor.cancel()
    }

    private func setupNetworkMonitor() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isExpensiveConnection = path.isExpensive
            }
        }
        pathMonitor.start(queue: DispatchQueue.global(qos: .background))
    }

    func startScanIfNeeded(localStore: LocalStore, force: Bool = false) {
        guard !isScanning else { return }
        
        let settings = localStore.settings()
        if isExpensiveConnection && !settings.scanOnCellular {
            logger.info("Expensive/cellular connection and Scan on Cellular is disabled. Skipping scan.")
            return
        }
        
        if !force {
            let now = Date().timeIntervalSince1970
            let lastScan = defaults.double(forKey: lastScanKey)
            guard now - lastScan >= scanCooldown else {
                logger.info("Cooldown active. Skipping scan.")
                return
            }
        }
        
        startScan(force: force)
    }

    func startScan(force: Bool = false) {
        guard !isScanning, let store = store else { return }
        isScanning = true
        if force {
            self.queue = store.channels
            logger.info("Starting forced scan. All channels in queue: \(self.queue.map { $0.title }, privacy: .public)")
        } else {
            self.queue = store.channels.filter { $0.isLiveExpected }
            logger.info("Starting scan. Live channels in queue: \(self.queue.map { $0.title }, privacy: .public)")
        }
        
        processNext()
    }

    private func loadHostPage() {
        guard let url = Bundle.main.url(forResource: "player", withExtension: "html"),
              let html = try? String(contentsOf: url, encoding: .utf8) else {
            return
        }
        webView.loadHTMLString(html, baseURL: URL(string: "https://20four7.fm.rodeo"))
    }

    func processNext() {
        guard isScanning else { return }
        guard let store = store else {
            finishScan()
            return
        }
        guard !queue.isEmpty else {
            finishScan()
            return
        }
        
        // Prioritize visible channels first, then selected tag channels next
        let channel: Channel
        if let visibleIndex = queue.firstIndex(where: { store.visibleChannelIDs.contains($0.id) }) {
            channel = queue.remove(at: visibleIndex)
            logger.info("Prioritizing visible channel: \(channel.title, privacy: .public)")
        } else if !store.selectedTagIDs.isEmpty,
                  let tagIndex = queue.firstIndex(where: { !store.selectedTagIDs.isDisjoint(with: $0.tagIDs) }) {
            channel = queue.remove(at: tagIndex)
            logger.info("Prioritizing channel matching selected tags: \(channel.title, privacy: .public)")
        } else {
            channel = queue.removeFirst()
        }
        currentChannel = channel
        logger.info("Processing next channel: \(channel.title, privacy: .public) (ID: \(channel.id, privacy: .public), YouTubeID: \(channel.youTubeVideoID, privacy: .public))")
        
        // Start 12-second timeout (accommodates cold start & slower network latency)
        timeoutTask?.cancel()
        timeoutTask = Task {
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            guard !Task.isCancelled else { return }
            logger.info("Timeout fired for channel: \(channel.title, privacy: .public)")
            handleDetectionResult(isLive: false, offline: true)
        }
        
        if apiReady {
            triggerCurrentLoad()
        } else {
            loadHostPage()
        }
    }

    private func triggerCurrentLoad() {
        guard let channel = currentChannel else { return }
        logger.info("triggerCurrentLoad for channel: \(channel.title, privacy: .public)")
        webView.evaluateJavaScript("loadVideo('\(channel.youTubeVideoID)', \(channel.isLiveExpected), true, true)", completionHandler: nil)
    }

    private func handleDetectionResult(isLive: Bool, offline: Bool) {
        timeoutTask?.cancel()
        timeoutTask = nil
        
        guard let channel = currentChannel, let store = store else { return }
        currentChannel = nil
        
        logger.info("handleDetectionResult for \(channel.title, privacy: .public) - isLive: \(isLive, privacy: .public), offline: \(offline, privacy: .public)")
        if offline {
            logger.info("Marking channel offline: \(channel.title, privacy: .public)")
            store.markChannelOffline(id: channel.id)
        } else {
            logger.info("Marking channel online: \(channel.title, privacy: .public)")
            store.markChannelOnline(id: channel.id)
            store.updateLiveStatus(channelID: channel.id, isLive: isLive)
        }
        
        delayTask?.cancel()
        delayTask = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second cooldown delay
            guard !Task.isCancelled else { return }
            processNext()
        }
    }

    private func finishScan() {
        isScanning = false
        timeoutTask?.cancel()
        timeoutTask = nil
        delayTask?.cancel()
        delayTask = nil
        currentChannel = nil
        defaults.set(Date().timeIntervalSince1970, forKey: lastScanKey)
        logger.info("Scan finished.")
    }

    func stopScan() {
        isScanning = false
        timeoutTask?.cancel()
        timeoutTask = nil
        delayTask?.cancel()
        delayTask = nil
        currentChannel = nil
        queue.removeAll()
        logger.info("Scan stopped.")
    }

    // MARK: WKScriptMessageHandler
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "apiReady":
            apiReady = true
            triggerCurrentLoad()
        case "isLive":
            let isLive = body["isLive"] as? Bool ?? false
            handleDetectionResult(isLive: isLive, offline: false)
        case "error":
            handleDetectionResult(isLive: false, offline: true)
        default:
            break
        }
    }
}
