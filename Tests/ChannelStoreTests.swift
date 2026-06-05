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
         "catalogUrl":"https://20four7.fm.rodeo/20four7/catalog-v1.json","minAppVersion":"1.0.0"}
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
         "catalogUrl":"https://20four7.fm.rodeo/20four7/catalog-v1.json","minAppVersion":"1.0.0"}
        """.data(using: .utf8)!
        
        let catalogJSON = """
        {"schemaVersion":1,
         "tags":{"rain":{"name":"Rain","symbol":"cloud.rain","sortOrder":1}},
         "channels":[
            {"id":"c1","title":"Rain","youTubeVideoID":"abcdefghij1","thumbnailURL":null,"isLiveExpected":true,"tagIds":["rain"]},
            {"id":"c2","title":"Offline Rain","youTubeVideoID":"abcdefghij2","thumbnailURL":null,"isLiveExpected":true,"tagIds":["rain"]}
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
        
        localStore.setLastPlayedDate(channelID: channelB.id, date: eightDaysAgo)
        localStore.setLastPlayedDate(channelID: channelC.id, date: eightDaysAgo)
        
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
        // Only "zen" should be selected.
        // "nature" has a tap count of 1, whereas "rain" has 0.
        // So "nature" sorts before "rain" in the unselected group.
        // Order: ["zen", "nature", "rain"]
        XCTAssertEqual(store.chipTags.map(\.id), ["zen", "nature", "rain"])
    }

    func test_favsChipLifecycle() throws {
        let localStore = try makeStore()
        localStore.addUserChannel(Channel(
            id: "u1", title: "U1", youTubeVideoID: "vvvvvvvvvvv",
            source: .user, isLiveExpected: true))
        let store = ChannelStore(remoteConfig: makeRemoteConfig(), localStore: localStore)

        // Hidden until there is at least one favorite.
        XCTAssertFalse(store.chipTags.contains { $0.id == Tag.favsID })

        let channel = try XCTUnwrap(store.channels.first { $0.id == "u1" })
        store.toggleFavorite(channel)

        // Appears, counts the favorite, and is pinned to the front.
        XCTAssertTrue(store.chipTags.contains { $0.id == Tag.favsID })
        XCTAssertEqual(store.tagChannelCounts[Tag.favsID], 1)
        XCTAssertEqual(store.chipTags.first?.id, Tag.favsID)

        // Disappears after the last favorite is removed.
        store.toggleFavorite(channel)
        XCTAssertFalse(store.chipTags.contains { $0.id == Tag.favsID })
    }

    func test_favsPinnedAheadOfOtherTags() throws {
        let localStore = try makeStore()
        localStore.addUserChannel(Channel(
            id: "u1", title: "U1", youTubeVideoID: "vvvvvvvvvvv",
            source: .user, isLiveExpected: true, tagIDs: ["nature"]))
        let store = ChannelStore(remoteConfig: makeRemoteConfig(), localStore: localStore)
        let channel = try XCTUnwrap(store.channels.first { $0.id == "u1" })

        store.toggleFavorite(channel)
        XCTAssertEqual(store.chipTags.first?.id, Tag.favsID)
    }

    func test_favsDeselectedWhenLastFavoriteRemoved() throws {
        let localStore = try makeStore()
        localStore.addUserChannel(Channel(
            id: "u1", title: "U1", youTubeVideoID: "vvvvvvvvvvv",
            source: .user, isLiveExpected: true))
        let store = ChannelStore(remoteConfig: makeRemoteConfig(), localStore: localStore)
        let channel = try XCTUnwrap(store.channels.first { $0.id == "u1" })

        store.toggleFavorite(channel)
        store.selectedTagIDs = [Tag.favsID]
        store.toggleFavorite(channel) // remove last favorite

        XCTAssertFalse(store.selectedTagIDs.contains(Tag.favsID))
    }

    func test_selectableTagsIncludesEditorialAndSelected() async throws {
        let localStore = try makeStore()
        let store = ChannelStore(remoteConfig: makeRemoteConfig(), localStore: localStore)
        await store.refresh()

        let tags = store.selectableTags(including: ["MyCustomTag"])
        let ids = tags.map(\.id)
        XCTAssertTrue(ids.contains("rain"))         // editorial, from catalog
        XCTAssertTrue(ids.contains("MyCustomTag"))  // a not-yet-existing selected id
        // Sorted by (sortOrder, name): editorial "rain" (1) before custom (100).
        XCTAssertLessThan(ids.firstIndex(of: "rain")!, ids.firstIndex(of: "MyCustomTag")!)
    }

    func test_editUserChannelUpdatesInPlace() async throws {
        let localStore = try makeStore()
        localStore.addUserChannel(Channel(id: "user-vid", title: "Old",
            youTubeVideoID: "vid12345678", source: .user, isLiveExpected: true, tagIDs: ["old"]))
        let store = ChannelStore(remoteConfig: makeRemoteConfig(), localStore: localStore)
        await store.refresh()

        let userChan = try XCTUnwrap(store.channels.first { $0.id == "user-vid" })
        store.editChannel(userChan, title: "New", tagIDs: ["zen"],
                          isLiveExpected: false, isFavorite: true)

        let updated = try XCTUnwrap(store.channels.first { $0.id == "user-vid" })
        XCTAssertEqual(updated.title, "New")
        XCTAssertEqual(updated.isLiveExpected, false)
        XCTAssertTrue(updated.tagIDs.contains("zen"))
        XCTAssertTrue(store.isFavorite(updated))
    }

    func test_editCuratedChannelAdoptsIt() async throws {
        let localStore = try makeStore()
        let store = ChannelStore(remoteConfig: makeRemoteConfig(), localStore: localStore)
        await store.refresh()

        // Curated channel c1 (video "abcdefghijk") with prior play history.
        _ = localStore.incrementPlayCount(channelID: "c1")
        await store.refresh()
        let curated = try XCTUnwrap(store.channels.first { $0.id == "c1" })

        store.editChannel(curated, title: "My Rain", tagIDs: ["rain", "cozy"],
                          isLiveExpected: false, isFavorite: true)

        // Curated original is gone; only the adopted user copy remains.
        XCTAssertNil(store.channels.first { $0.id == "c1" })
        let adopted = try XCTUnwrap(store.channels.first { $0.id == "user-abcdefghijk" })
        XCTAssertEqual(adopted.source, .user)
        XCTAssertEqual(adopted.title, "My Rain")
        XCTAssertTrue(adopted.tagIDs.contains("cozy"))
        XCTAssertEqual(adopted.isLiveExpected, false)
        XCTAssertTrue(store.isFavorite(adopted))
        XCTAssertEqual(adopted.playCount, 1) // history carried over

        // Old curated state row is cleaned up.
        XCTAssertNil(localStore.allUserStates().first { $0.channelID == "c1" })
    }

    func test_removingAdoptedChannelDoesNotRevealCuratedTwin() async throws {
        let localStore = try makeStore()
        let store = ChannelStore(remoteConfig: makeRemoteConfig(), localStore: localStore)
        await store.refresh()

        // Adopt curated c1 (video "abcdefghijk") into a user copy.
        let curated = try XCTUnwrap(store.channels.first { $0.id == "c1" })
        store.editChannel(curated, title: "Mine", tagIDs: ["rain"],
                          isLiveExpected: true, isFavorite: false)
        let adopted = try XCTUnwrap(store.channels.first { $0.id == "user-abcdefghijk" })

        // Remove the adopted copy.
        store.removeChannel(adopted)

        XCTAssertNil(store.channels.first { $0.id == "user-abcdefghijk" })
        XCTAssertNil(store.channels.first { $0.id == "c1" })
        XCTAssertEqual(store.filteredChannels.count, 0)
    }

    func test_editChannelRefreshesRecency() throws {
        let localStore = try makeStore()
        let remoteConfig = makeRemoteConfig()

        // Seed a user channel with a stale lastPlayedDate.
        let userChannel = Channel(
            id: "user-vid", title: "Old Title", youTubeVideoID: "abcdefghijk",
            source: .user, isLiveExpected: true, tagIDs: ["mine"])
        localStore.addUserChannel(userChannel)
        let stale = Date(timeIntervalSince1970: 0)
        _ = localStore.recordWatch(channelID: "user-vid", seconds: 5, date: stale)

        let store = ChannelStore(remoteConfig: remoteConfig, localStore: localStore)
        let original = try XCTUnwrap(store.channels.first { $0.id == "user-vid" })
        XCTAssertEqual(original.lastPlayedDate, stale)
        let watchBefore = original.watchSeconds

        let before = Date()
        store.editChannel(original, title: "New Title", tagIDs: ["mine"],
                          isLiveExpected: true, isFavorite: false)

        let edited = try XCTUnwrap(store.channels.first { $0.id == "user-vid" })
        // Recency refreshed (lastPlayedDate ~ now)...
        let lp = try XCTUnwrap(edited.lastPlayedDate)
        XCTAssertGreaterThanOrEqual(lp, before)
        // ...but no lasting score added: watchSeconds unchanged.
        XCTAssertEqual(edited.watchSeconds, watchBefore, accuracy: 0.0001)
    }

    func test_searchQueryFiltering() async throws {
        let localStore = try makeStore()
        
        let c1 = Channel(id: "u1", title: "Nature Sanctuary", youTubeVideoID: "v1", source: .user, isLiveExpected: true, tagIDs: ["nature"])
        let c2 = Channel(id: "u2", title: "Lofi Beats", youTubeVideoID: "v2", source: .user, isLiveExpected: true, tagIDs: ["lofi"])
        let c3 = Channel(id: "u3", title: "Cozy Fireplace", youTubeVideoID: "v3", source: .user, isLiveExpected: true, tagIDs: ["cozy"])
        localStore.addUserChannel(c1)
        localStore.addUserChannel(c2)
        localStore.addUserChannel(c3)
        
        let store = ChannelStore(remoteConfig: makeRemoteConfig(), localStore: localStore)
        await store.refresh()
        
        // Initially, 4 channels (including mock catalog's c1 which has title "Rain")
        XCTAssertEqual(store.filteredChannels.count, 4)
        
        // Search by title substring
        store.searchQuery = "nature"
        XCTAssertEqual(store.filteredChannels.map(\.id), ["u1"])
        
        // Search by tag name
        store.searchQuery = "lofi"
        XCTAssertEqual(store.filteredChannels.map(\.id), ["u2"])
        
        // Test composition: tag filter AND search query
        store.selectedTagIDs = ["nature"]
        store.searchQuery = ""
        XCTAssertEqual(store.filteredChannels.map(\.id), ["u1"])
        
        // Search for "beats" within tag "nature" -> yields 0 matches
        store.searchQuery = "beats"
        XCTAssertEqual(store.filteredChannels.count, 0)
        
        // Clear search -> yields the "nature" channel again
        store.searchQuery = ""
        XCTAssertEqual(store.filteredChannels.map(\.id), ["u1"])
    }

    func test_searchRanksByMatchScoreOverPopularity() async throws {
        let localStore = try makeStore()

        // An exact-match channel with no play history, and a loose fuzzy match
        // ("rain" as a scattered subsequence of "Relaxing And Intense") made far
        // more popular. Score ranking must still float the exact match first.
        let exact = Channel(id: "exact", title: "Rain", youTubeVideoID: "rain0000001",
                            source: .user, isLiveExpected: true, tagIDs: ["weather"])
        let loose = Channel(id: "loose", title: "Relaxing And Intense", youTubeVideoID: "relax000001",
                            source: .user, isLiveExpected: true, tagIDs: ["weather"])
        localStore.addUserChannel(exact)
        localStore.addUserChannel(loose)
        for _ in 1...20 { localStore.incrementPlayCount(channelID: "loose") }

        let store = ChannelStore(remoteConfig: makeRemoteConfig(), localStore: localStore)
        await store.refresh()

        store.searchQuery = "rain"
        let ids = store.filteredChannels.map(\.id)
        XCTAssertTrue(ids.contains("exact"))
        // Despite "loose" being far more popular, the tighter match ranks first.
        if let exactIdx = ids.firstIndex(of: "exact"), let looseIdx = ids.firstIndex(of: "loose") {
            XCTAssertLessThan(exactIdx, looseIdx)
        }
    }
}
