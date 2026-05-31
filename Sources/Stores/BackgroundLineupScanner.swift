import Foundation
import WebKit
import Network

@MainActor
final class BackgroundLineupScanner: NSObject, WKScriptMessageHandler {
    private let store: ChannelStore
    private(set) var webView: WKWebView!
    private(set) var queue: [Channel] = []
    private(set) var currentChannel: Channel?
    private(set) var isScanning = false
    private var apiReady = false
    
    private let pathMonitor = NWPathMonitor()
    private var isExpensiveConnection = false
    
    private let lastScanKey = "com.televista.lastScanTime"
    private let scanCooldown: TimeInterval = 6 * 3600 // 6 hours
    private var timeoutTask: Task<Void, Never>?

    init(store: ChannelStore) {
        self.store = store
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
            print("BackgroundLineupScanner: Expensive/cellular connection and Scan on Cellular is disabled. Skipping scan.")
            return
        }
        
        if !force {
            let now = Date().timeIntervalSince1970
            let lastScan = UserDefaults.standard.double(forKey: lastScanKey)
            guard now - lastScan >= scanCooldown else {
                print("BackgroundLineupScanner: Cooldown active. Skipping scan.")
                return
            }
        }
        
        startScan(force: force)
    }

    func startScan(force: Bool = false) {
        guard !isScanning else { return }
        isScanning = true
        if force {
            queue = store.channels
            print("BackgroundLineupScanner: Starting forced scan. All channels in queue: \(queue.map { $0.title })")
        } else {
            queue = store.channels.filter { $0.isLiveExpected }
            print("BackgroundLineupScanner: Starting scan. Live channels in queue: \(queue.map { $0.title })")
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

    private func processNext() {
        guard isScanning, !queue.isEmpty else {
            finishScan()
            return
        }
        
        // Prioritize visible channels first, then selected tag channels next
        let channel: Channel
        if let visibleIndex = queue.firstIndex(where: { store.visibleChannelIDs.contains($0.id) }) {
            channel = queue.remove(at: visibleIndex)
            print("BackgroundLineupScanner: Prioritizing visible channel: \(channel.title)")
        } else if !store.selectedTagIDs.isEmpty,
                  let tagIndex = queue.firstIndex(where: { !store.selectedTagIDs.isDisjoint(with: $0.tagIDs) }) {
            channel = queue.remove(at: tagIndex)
            print("BackgroundLineupScanner: Prioritizing channel matching selected tags: \(channel.title)")
        } else {
            channel = queue.removeFirst()
        }
        currentChannel = channel
        print("BackgroundLineupScanner: Processing next channel: \(channel.title) (ID: \(channel.id), YouTubeID: \(channel.youTubeVideoID))")
        
        // Start 6-second timeout
        timeoutTask?.cancel()
        timeoutTask = Task {
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard !Task.isCancelled else { return }
            print("BackgroundLineupScanner: Timeout fired for channel: \(channel.title)")
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
        print("BackgroundLineupScanner: triggerCurrentLoad for channel: \(channel.title)")
        webView.evaluateJavaScript("loadVideo('\(channel.youTubeVideoID)', \(channel.isLiveExpected), true, true)", completionHandler: nil)
    }

    private func handleDetectionResult(isLive: Bool, offline: Bool) {
        timeoutTask?.cancel()
        timeoutTask = nil
        
        guard let channel = currentChannel else { return }
        currentChannel = nil
        
        print("BackgroundLineupScanner: handleDetectionResult for \(channel.title) - isLive: \(isLive), offline: \(offline)")
        if offline {
            print("BackgroundLineupScanner: Marking channel offline: \(channel.title)")
            store.markChannelOffline(id: channel.id)
        } else {
            print("BackgroundLineupScanner: Marking channel online: \(channel.title)")
            store.markChannelOnline(id: channel.id)
            store.updateLiveStatus(channelID: channel.id, isLive: isLive)
        }
        
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second cooldown delay
            processNext()
        }
    }

    private func finishScan() {
        isScanning = false
        timeoutTask?.cancel()
        timeoutTask = nil
        currentChannel = nil
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastScanKey)
        print("BackgroundLineupScanner: Scan finished.")
    }

    func stopScan() {
        isScanning = false
        timeoutTask?.cancel()
        timeoutTask = nil
        currentChannel = nil
        queue.removeAll()
        print("BackgroundLineupScanner: Scan stopped.")
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
