import Foundation
import SwiftData

enum Persistence {
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([UserChannel.self, ChannelUserState.self, AppSettingsRecord.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            if !inMemory {
                let storeURL = URL.applicationSupportDirectory.appending(path: "default.store")
                let shmURL = URL.applicationSupportDirectory.appending(path: "default.store-shm")
                let walURL = URL.applicationSupportDirectory.appending(path: "default.store-wal")
                let fm = FileManager.default
                try? fm.removeItem(at: storeURL)
                try? fm.removeItem(at: shmURL)
                try? fm.removeItem(at: walURL)
                return try ModelContainer(for: schema, configurations: [config])
            }
            throw error
        }
    }
}
