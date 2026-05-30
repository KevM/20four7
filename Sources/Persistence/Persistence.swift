import Foundation
import SwiftData

enum Persistence {
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([UserChannel.self, ChannelUserState.self, AppSettingsRecord.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [config])
    }
}
