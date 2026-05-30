import SwiftUI
import SwiftData
import AVFoundation

@main
struct TwentyFourSevenApp: App {
    @StateObject private var env: AppEnvironment

    init() {
        // Configure AVAudioSession for background audio playback
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playback, mode: .moviePlayback, options: [])
            try audioSession.setActive(true)
        } catch {
            print("Failed to set AVAudioSession category: \(error)")
        }

        // Under XCTest the app host launches before the tests; using the
        // on-disk store there spams CoreData errors on fresh simulators and
        // can leak state between runs. Tests own their own in-memory store.
        let underTests = NSClassFromString("XCTestCase") != nil
        let container = (try? Persistence.makeContainer(inMemory: underTests)) ?? {
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
