import Foundation
import SwiftData

/// Wires concrete dependencies together once, at launch.
@MainActor
final class AppEnvironment: ObservableObject {
    let localStore: LocalStore
    let channelStore: ChannelStore
    let player: WebViewPlayerService
    let controller: PlaybackController

    init(container: ModelContainer) {
        let local = LocalStore(context: container.mainContext)
        let cache = FileCatalogCache()
        let bundled = AppEnvironment.loadBundledCatalog()
        let appVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0.0"
        let remote = RemoteConfig(
            baseURL: Config.catalogBaseURL, session: .shared, cache: cache,
            supportedSchema: Config.supportedSchemaVersion, appVersion: appVersion,
            bundledLoader: { bundled })
        let store = ChannelStore(remoteConfig: remote, localStore: local)
        let webPlayer = WebViewPlayerService()
        let playback = PlaybackController(player: webPlayer, clock: SystemClock(), channelStore: store)

        self.localStore = local
        self.channelStore = store
        self.player = webPlayer
        self.controller = playback

        playback.onChannelChanged = { [weak local, weak store] channel in
            local?.setLastWatched(channelID: channel.id)
            local?.incrementPlayCount(channelID: channel.id)
            Task { @MainActor in
                store?.reloadLineup()
            }
        }
    }

    private static func loadBundledCatalog() -> Catalog {
        guard let url = Bundle.main.url(forResource: "catalog-fallback", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? Catalog.decode(from: data) else {
            return Catalog(schemaVersion: 1, tags: [:], channels: [])
        }
        return catalog
    }
}
