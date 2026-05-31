import XCTest
import SwiftData
import WebKit
@testable import TwentyFourSeven

@MainActor
final class BackgroundLineupScannerTests: XCTestCase {
    private func makeStore() throws -> (LocalStore, ChannelStore) {
        let container = try Persistence.makeContainer(inMemory: true)
        let localStore = LocalStore(context: container.mainContext)
        
        let manifestJSON = "{\"schemaVersion\":1,\"catalogVersion\":1,\"catalogUrl\":\"https://example.com\",\"minAppVersion\":\"1.0.0\"}".data(using: .utf8)!
        let catalogJSON = "{\"schemaVersion\":1,\"tags\":{},\"channels\":[]}".data(using: .utf8)!
        
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: cfg)
        StubURLProtocol.routes = [
            "channels-manifest.json": (200, manifestJSON, [:]),
            "catalog-v1.json": (200, catalogJSON, [:])
        ]
        
        let remote = RemoteConfig(
            baseURL: Config.catalogBaseURL, session: session, cache: MemoryCatalogCache(),
            supportedSchema: 1, appVersion: "1.0.0", bundledLoader: { Catalog(schemaVersion: 1, tags: [:], channels: []) }
        )
        
        let store = ChannelStore(remoteConfig: remote, localStore: localStore)
        return (localStore, store)
    }

    private func testDefaults() -> UserDefaults {
        let suite = "com.televista.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func test_scanner_respects_cooldown() throws {
        let (localStore, store) = try makeStore()
        
        // Add a channel so that scanner queue is not empty and doesn't immediately call finishScan()
        let userChannel = Channel(id: "user-ch1", title: "Test Video", youTubeVideoID: "123", source: .user, isLiveExpected: true)
        localStore.addUserChannel(userChannel)
        store.restoreRemovedChannels()
        
        let defaults = testDefaults()
        let scanner = BackgroundLineupScanner(store: store, defaults: defaults)
        
        let lastScanKey = "com.televista.lastScanTime"
        
        // 1. Manually set cooldown timestamp to simulate completed scan
        defaults.set(Date().timeIntervalSince1970, forKey: lastScanKey)
        
        // 2. Scan if needed right after should be blocked by cooldown
        scanner.startScanIfNeeded(localStore: localStore)
        XCTAssertFalse(scanner.isScanning)
        
        // 3. Force scan should bypass cooldown
        scanner.startScanIfNeeded(localStore: localStore, force: true)
        XCTAssertTrue(scanner.isScanning)
        scanner.stopScan()
        XCTAssertFalse(scanner.isScanning)
        
        // 4. Temporarily reset cooldown and check if it runs normally
        defaults.set(0.0, forKey: lastScanKey)
        scanner.startScanIfNeeded(localStore: localStore)
        XCTAssertTrue(scanner.isScanning)
        scanner.stopScan()
    }

    func test_messageHandlerRegistration() async throws {
        let config = WKWebViewConfiguration()
        let web = WKWebView(frame: .zero, configuration: config)
        
        class TestHandler: NSObject, WKScriptMessageHandler {
            var received = false
            let expectation: XCTestExpectation
            
            init(expectation: XCTestExpectation) {
                self.expectation = expectation
                super.init()
            }
            
            func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
                received = true
                expectation.fulfill()
            }
        }
        
        let expectation = self.expectation(description: "Message received")
        let handler = TestHandler(expectation: expectation)
        config.userContentController.add(handler, name: "testHandler")
        
        // Evaluate javascript to send message
        do {
            _ = try await web.evaluateJavaScript("window.webkit.messageHandlers.testHandler.postMessage('hello')")
        } catch {
            print("Error evaluating JS: \(error)")
        }
        
        await fulfillment(of: [expectation], timeout: 2.0)
    }

    func test_scanner_prioritizes_queue() throws {
        let (localStore, store) = try makeStore()
        
        let c1 = Channel(id: "user-c1", title: "Lofi Video", youTubeVideoID: "111", source: .user, isLiveExpected: true, tagIDs: ["lofi"])
        let c2 = Channel(id: "user-c2", title: "Nature Video", youTubeVideoID: "222", source: .user, isLiveExpected: true, tagIDs: ["nature"])
        let c3 = Channel(id: "user-c3", title: "Fireplace Video", youTubeVideoID: "333", source: .user, isLiveExpected: true, tagIDs: ["fireplace"])
        
        localStore.addUserChannel(c1)
        localStore.addUserChannel(c2)
        localStore.addUserChannel(c3)
        store.restoreRemovedChannels()
        
        // Mark c3 as visible
        store.markChannelVisible("user-c3")
        
        // Select 'nature' tag
        store.selectedTagIDs = ["nature"]
        
        let defaults = testDefaults()
        let scanner = BackgroundLineupScanner(store: store, defaults: defaults)
        
        // Bypass cooldown to start scanning
        let lastScanKey = "com.televista.lastScanTime"
        defaults.set(0.0, forKey: lastScanKey)
        
        scanner.startScan()
        
        // First channel popped should be the visible channel: c3
        XCTAssertEqual(scanner.currentChannel?.id, "user-c3")
        
        // Manually trigger the next process steps to check pop priority
        scanner.processNext()
        XCTAssertEqual(scanner.currentChannel?.id, "user-c2") // Tag priority
        
        scanner.processNext()
        XCTAssertEqual(scanner.currentChannel?.id, "user-c1") // Rest
        
        scanner.stopScan()
    }

    func test_scanner_skips_vod_unless_forced() throws {
        let (localStore, store) = try makeStore()
        
        let c1 = Channel(id: "user-c1", title: "Live Video", youTubeVideoID: "111", source: .user, isLiveExpected: true)
        let c2 = Channel(id: "user-c2", title: "VOD Video", youTubeVideoID: "222", source: .user, isLiveExpected: false)
        
        localStore.addUserChannel(c1)
        localStore.addUserChannel(c2)
        store.restoreRemovedChannels()
        
        let defaults = testDefaults()
        let scanner = BackgroundLineupScanner(store: store, defaults: defaults)
        let lastScanKey = "com.televista.lastScanTime"
        defaults.set(0.0, forKey: lastScanKey)
        
        // 1. Normal scan should filter out VOD channel (c2)
        scanner.startScan(force: false)
        XCTAssertEqual(scanner.currentChannel?.id, "user-c1")
        XCTAssertTrue(scanner.queue.isEmpty) // queue has 0 elements since c2 was excluded
        scanner.stopScan()
        
        // 2. Forced scan should include both VOD channel (c2) and live channel (c1)
        scanner.startScan(force: true)
        let processedID = scanner.currentChannel?.id
        let queuedIDs = scanner.queue.map { $0.id }
        
        var allScannedIDs = queuedIDs
        if let processed = processedID {
            allScannedIDs.append(processed)
        }
        XCTAssertEqual(Set(allScannedIDs), Set(["user-c1", "user-c2"]))
        
        scanner.stopScan()
    }
}
