import SwiftUI
import SwiftData

@main
struct TwentyFourSevenApp: App {
    @StateObject private var env: AppEnvironment

    init() {
        let container = (try? Persistence.makeContainer()) ?? {
            // Fall back to in-memory if the on-disk store can't be opened.
            try! Persistence.makeContainer(inMemory: true)
        }()
        _env = StateObject(wrappedValue: AppEnvironment(container: container))
    }

    var body: some Scene {
        WindowGroup {
            RootView(env: env)
                .preferredColorScheme(.dark)
        }
    }
}
