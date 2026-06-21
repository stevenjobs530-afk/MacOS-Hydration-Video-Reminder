import SwiftUI

struct SettingsView: View {
    @ObservedObject var controller: AppController
    @ObservedObject private var store: SettingsStore

    init(controller: AppController) {
        self.controller = controller
        store = controller.settingsStore
    }

    var body: some View {
        Form {
            Section("Reminder") {
                Toggle("Reminders enabled", isOn: $store.settings.remindersEnabled)
                Toggle("Launch at login", isOn: $store.settings.launchAtLoginEnabled)
                Text("Launch at login is recorded for the MVP; the install script still owns the actual LaunchAgent setup.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Playback") {
                Picker("Playback mode", selection: $store.settings.playbackMode) {
                    ForEach(VideoPlaybackMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                Slider(value: $store.settings.reminderVolume, in: 0...100, step: 1) {
                    Text("Volume")
                }
                Text("Reminder volume: \(Int(store.settings.reminderVolume))%")
                    .foregroundStyle(.secondary)
            }

            Section("Today") {
                Text(store.isPausedToday ? "Today is paused" : "Today is running")
                HStack {
                    Button("Pause Today") {
                        controller.pauseToday()
                    }
                    Button("Resume Today") {
                        controller.resumeToday()
                    }
                }
            }

            Section {
                Button("Restore Defaults") {
                    store.restoreDefaults()
                }
            }
        }
        .padding(24)
        .navigationTitle("Settings")
    }
}
