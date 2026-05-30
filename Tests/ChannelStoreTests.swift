import XCTest
import SwiftData
import Combine
@testable import Televista

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
         "catalogUrl":"https://cdn.example.com/televista/catalog-v1.json","minAppVersion":"1.0.0"}
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
}
