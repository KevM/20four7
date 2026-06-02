import XCTest
import SwiftData
import Combine
@testable import TwentyFourSeven

@MainActor
final class ChannelStoreTests: XCTestCase {
    private func makeStore() throws -> LocalStore {
        let container = try Persistence.makeContainer(inMemory: true)
        return LocalStore(context: container.mainContext)
    }

    private func makeRemoteConfig() -> RemoteConfig {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: cfg)
        
        let manifestJSON = """
        {"schemaVersion":1,"catalogVersion":1,
         "catalogUrl":"https://cdn.example.com/20four7/catalog-v1.json","minAppVersion":"1.0.0"}
        """.data(using: .utf8)!
        
        let catalogJSON = """
        {"schemaVersion":1,
         "tags":{"rain":{"name":"Rain","symbol":"cloud.rain","sortOrder":1}},
         "channels":[{"id":"c1","title":"Rain","youTubeVideoID":"abcdefghijk",
           "thumbnailURL":null,"isLiveExpected":true,"tagIds":["rain"]}]}
        """.data(using: .utf8)!
        
        StubURLProtocol.routes = [
            "channels-manifest.json": (200, manifestJSON, [:]),
            "catalog-v1.json": (200, catalogJSON, [:]),
        ]
        
        return RemoteConfig(
            baseURL: Config.catalogBaseURL,
            session: session,
            cache: MemoryCatalogCache(),
            supportedSchema: 1,
            appVersion: "1.0.0",
            bundledLoader: {
                Catalog(schemaVersion: 1, tags: [:], channels: [])
            }
        )
    }

    func test_refreshExtractsUserTagsAndResolvesThem() async throws {
        let localStore = try makeStore()
        let remoteConfig = makeRemoteConfig()
        let store = ChannelStore(remoteConfig: remoteConfig, localStore: localStore)
        
        // 1. Pre-populate user channels with custom tags
        let userChannel = Channel(
            id: "user-video",
            title: "Custom Nature Stream",
            youTubeVideoID: "12345678901",
            source: .user,
            isLiveExpected: true,
            tagIDs: ["Nature", "rain"] // "rain" is editorial, "Nature" is custom user tag
        )
        localStore.addUserChannel(userChannel)
        
        // 2. Perform refresh
        await store.refresh()
        
        // 3. Verify user tag is dynamically generated
        let tags = store.tagsByID
        XCTAssertNotNil(tags["Nature"])
        XCTAssertEqual(tags["Nature"]?.name, "Nature")
        XCTAssertEqual(tags["Nature"]?.kind, .user)
        XCTAssertEqual(tags["Nature"]?.sortOrder, 100)
        
        // 4. Verify resolving tags works for custom tag
        let resolved = store.resolveTags(userChannel)
        XCTAssertEqual(resolved.count, 2)
        XCTAssertTrue(resolved.contains { $0.id == "Nature" })
        XCTAssertTrue(resolved.contains { $0.id == "rain" })
        
        // 5. Verify chipTags includes the custom tag, de-duplicated and sorted
        let chips = store.chipTags
        XCTAssertEqual(chips.count, 2)
        XCTAssertEqual(chips[0].id, "rain") // sortOrder 1
        XCTAssertEqual(chips[1].id, "Nature") // sortOrder 100
    }

    func test_filtersOfflineChannelsBasedOnSettings() async throws {
        let localStore = try makeStore()
        
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: cfg)
        
        let manifestJSON = """
        {"schemaVersion":1,"catalogVersion":1,
         "catalogUrl":"https://cdn.example.com/20four7/catalog-v1.json","minAppVersion":"1.0.0"}
        """.data(using: .utf8)!
        
        let catalogJSON = """
        {"schemaVersion":1,
         "tags":{"rain":{"name":"Rain","symbol":"cloud.rain","sortOrder":1}},
         "channels":[
            {"id":"c1","title":"Rain","youTubeVideoID":"abc","thumbnailURL":null,"isLiveExpected":true,"tagIds":["rain"]},
            {"id":"c2","title":"Offline Rain","youTubeVideoID":"def","thumbnailURL":null,"isLiveExpected":true,"tagIds":["rain"]}
         ]}
        """.data(using: .utf8)!
        
        StubURLProtocol.routes = [
            "channels-manifest.json": (200, manifestJSON, [:]),
            "catalog-v1.json": (200, catalogJSON, [:]),
        ]
        
        let remoteConfig = RemoteConfig(
            baseURL: Config.catalogBaseURL,
            session: session,
            cache: MemoryCatalogCache(),
            supportedSchema: 1,
            appVersion: "1.0.0",
            bundledLoader: {
                Catalog(schemaVersion: 1, tags: [:], channels: [])
            }
        )
        
        let store = ChannelStore(remoteConfig: remoteConfig, localStore: localStore)
        
        // 1. Refresh and mark 'c2' offline programmatically
        await store.refresh()
        store.markChannelOffline(id: "c2")
        
        // By default, showOffline is false, so offline channel 'c2' should be filtered out
        XCTAssertFalse(store.showOffline)
        XCTAssertEqual(store.filteredChannels.map(\.id), ["c1"])
        
        // 2. Enable showOffline setting and verify 'c2' is included after refresh
        var s = localStore.settings()
        s.showOffline = true
        localStore.saveSettings(s)
        
        await store.refresh()
        store.markChannelOffline(id: "c2")
        
        XCTAssertTrue(store.showOffline)
        XCTAssertEqual(store.filteredChannels.map(\.id).sorted(), ["c1", "c2"])
    }

    func test_store_renames_curated_and_user_channels() async throws {
        let localStore = try makeStore()
        let remoteConfig = makeRemoteConfig()
        let store = ChannelStore(remoteConfig: remoteConfig, localStore: localStore)
        
        await store.refresh()
        XCTAssertEqual(store.channels.count, 1)
        
        let original = store.channels[0]
        XCTAssertEqual(original.title, "Rain")
        
        // 1. Rename curated channel
        store.renameChannel(original, to: "Heavy Rain")
        XCTAssertEqual(store.channels.first?.title, "Heavy Rain")
        
        // Verify override persists in localStore
        let states = localStore.allUserStates()
        XCTAssertEqual(states.first(where: { $0.channelID == original.id })?.customTitle, "Heavy Rain")
        
        // 2. Rename user channel
        let userChan = Channel(id: "user-chan", title: "Custom Stream", youTubeVideoID: "123", source: .user, isLiveExpected: true)
        localStore.addUserChannel(userChan)
        await store.refresh()
        
        let addedUserChan = store.channels.first(where: { $0.id == "user-chan" })!
        store.renameChannel(addedUserChan, to: "Nature Ambient")
        
        XCTAssertEqual(store.channels.first(where: { $0.id == "user-chan" })?.title, "Nature Ambient")
        XCTAssertEqual(localStore.userChannels().first?.title, "Nature Ambient")
    }

    func test_store_hides_and_restores_channels() async throws {
        let localStore = try makeStore()
        let remoteConfig = makeRemoteConfig()
        let store = ChannelStore(remoteConfig: remoteConfig, localStore: localStore)
        
        await store.refresh()
        XCTAssertEqual(store.filteredChannels.count, 1)
        
        let chan = store.channels[0]
        
        // Remove curated channel -> hides it
        store.removeChannel(chan)
        XCTAssertEqual(store.filteredChannels.count, 0)
        XCTAssertTrue(store.hasRemovedChannels)
        
        // Restore all hidden channels
        store.restoreRemovedChannels()
        XCTAssertEqual(store.filteredChannels.count, 1)
        XCTAssertFalse(store.hasRemovedChannels)
    }

    func test_store_updates_live_status() async throws {
        let localStore = try makeStore()
        let remoteConfig = makeRemoteConfig()
        let store = ChannelStore(remoteConfig: remoteConfig, localStore: localStore)
        
        await store.refresh()
        let chan = store.channels[0]
        XCTAssertTrue(chan.isLiveExpected)
        
        // Update live status to false (VOD loop detected)
        store.updateLiveStatus(channelID: chan.id, isLive: false)
        XCTAssertFalse(store.channels[0].isLiveExpected)
        
        // Verify override is in DB
        let state = localStore.allUserStates().first(where: { $0.channelID == chan.id })
        XCTAssertEqual(state?.isLiveExpectedOverride, false)
    }

    func test_tagSortingByVisitsAndContentDensity() async throws {
        let localStore = try makeStore()
        let remoteConfig = makeRemoteConfig()
        
        // Setup channels with tags.
        // "zen" is alphabetically after "rain", but will have 2 channels (higher density).
        // "rain" will have 1 channel from the catalog.
        let userChannel1 = Channel(id: "u1", title: "C1", youTubeVideoID: "123", source: .user, isLiveExpected: true, tagIDs: ["zen"])
        let userChannel2 = Channel(id: "u2", title: "C2", youTubeVideoID: "456", source: .user, isLiveExpected: true, tagIDs: ["zen"])
        localStore.addUserChannel(userChannel1)
        localStore.addUserChannel(userChannel2)
        
        let store = ChannelStore(remoteConfig: remoteConfig, localStore: localStore)
        await store.refresh()
        
        // "zen" (density 2) should be sorted before "rain" (density 1),
        // proving density sorting overrides alphabetical order ("rain" before "zen").
        XCTAssertEqual(store.chipTags.map(\.id), ["zen", "rain"])
        
        // Tap "rain", visit count increments to 1
        store.toggleTag("rain")
        
        // Reload lineup to apply the sorting update (simulating a new session/launch/refresh)
        store.reloadLineup()
        
        // Now "rain" (1 visit) should bubble before "zen" (0 visits),
        // proving popularity sorting overrides density sorting.
        XCTAssertEqual(store.chipTags.map(\.id), ["rain", "zen"])
    }

    func test_popularityAndRecencySorting() async throws {
        let localStore = try makeStore()
        
        let now = Date()
        let eightDaysAgo = now.addingTimeInterval(-8.0 * 24.0 * 3600.0)
        
        let channelA = Channel(
            id: "user-chanA",
            title: "Channel A (New)",
            youTubeVideoID: "videoA12345",
            source: .user,
            isLiveExpected: true,
            dateAdded: now,
            tagIDs: ["rain"]
        )
        let channelB = Channel(
            id: "user-chanB",
            title: "Channel B (Old Popular)",
            youTubeVideoID: "videoB12345",
            source: .user,
            isLiveExpected: true,
            dateAdded: eightDaysAgo,
            tagIDs: ["rain"]
        )
        let channelC = Channel(
            id: "user-chanC",
            title: "Channel C (Old Unpopular)",
            youTubeVideoID: "videoC12345",
            source: .user,
            isLiveExpected: true,
            dateAdded: eightDaysAgo,
            tagIDs: ["rain"]
        )
        
        localStore.addUserChannel(channelA)
        localStore.addUserChannel(channelB)
        localStore.addUserChannel(channelC)
        
        for _ in 1...3 {
            localStore.incrementPlayCount(channelID: channelB.id)
        }
        localStore.incrementPlayCount(channelID: channelC.id)
        
        let remoteConfig = makeRemoteConfig()
        let store = ChannelStore(remoteConfig: remoteConfig, localStore: localStore)
        await store.refresh()
        
        store.selectedTagIDs = ["rain"]
        
        XCTAssertEqual(store.filteredChannels.map(\.id), [channelA.id, channelB.id, channelC.id, "c1"])
        
        for _ in 1...10 {
            localStore.incrementPlayCount(channelID: channelC.id)
        }
        
        store.reloadLineup()
        
        XCTAssertEqual(store.filteredChannels.map(\.id), [channelC.id, channelA.id, channelB.id, "c1"])
    }

    func test_selectedTagsArePromotedToFront() async throws {
        let localStore = try makeStore()
        let remoteConfig = makeRemoteConfig()
        
        // zen (sortOrder 100), rain (sortOrder 1 - from catalog), nature (sortOrder 100)
        let userChannel1 = Channel(id: "u1", title: "C1", youTubeVideoID: "123", source: .user, isLiveExpected: true, tagIDs: ["zen"])
        let userChannel2 = Channel(id: "u2", title: "C2", youTubeVideoID: "456", source: .user, isLiveExpected: true, tagIDs: ["nature"])
        localStore.addUserChannel(userChannel1)
        localStore.addUserChannel(userChannel2)
        
        let store = ChannelStore(remoteConfig: remoteConfig, localStore: localStore)
        await store.refresh()
        
        // Base order check: rain (sortOrder 1), nature (sortOrder 100), zen (sortOrder 100)
        // Wait, "nature" is alphabetically before "zen", so it should be: ["rain", "nature", "zen"]
        XCTAssertEqual(store.chipTags.map(\.id), ["rain", "nature", "zen"])
        
        // 1. Select the middle tag "nature"
        store.toggleTag("nature")
        // "nature" should float to the front
        XCTAssertEqual(store.chipTags.map(\.id), ["nature", "rain", "zen"])
        
        // 2. Select the last tag "zen"
        store.toggleTag("zen")
        // Both "nature" and "zen" should float to the front.
        // Between them, "nature" is before "zen" alphabetically. So the order should be: ["nature", "zen", "rain"]
        XCTAssertEqual(store.chipTags.map(\.id), ["nature", "zen", "rain"])
        
        // 3. Deselect "nature"
        store.toggleTag("nature")
        // Only "zen" should be selected. Order: ["zen", "rain", "nature"]
        XCTAssertEqual(store.chipTags.map(\.id), ["zen", "rain", "nature"])
    }
}

