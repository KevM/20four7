import SwiftUI

struct SettingsView: View {
    let localStore: LocalStore
    @State private var settings: AppSettings

    init(localStore: LocalStore) {
        self.localStore = localStore
        _settings = State(initialValue: localStore.settings())
    }

    var body: some View {
        Form {
            Section("Playback") {
                Toggle("Auto-resume last channel", isOn: $settings.autoResume)
                Stepper("Default sleep timer: \(settings.defaultSleepMinutes) min",
                        value: $settings.defaultSleepMinutes, in: 5...120, step: 5)
            }
            Section("Display") {
                Toggle("Show clock overlay", isOn: $settings.showClockOverlay)
                Picker("Dim level", selection: $settings.dimLevelRaw) {
                    Text("None").tag(0); Text("Low").tag(1); Text("Medium").tag(2); Text("High").tag(3)
                }
            }
        }
        .navigationTitle("Settings")
        .onChange(of: settings) { _, newValue in localStore.saveSettings(newValue) }
    }
}
