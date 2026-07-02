import Combine
import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings {
        didSet { save() }
    }

    private let fileURL: URL

    init(paths: AppPaths) {
        fileURL = paths.appSupportDirectory.appendingPathComponent("settings.json")
        settings = JSONFileStore.load(AppSettings.self, from: fileURL, fallback: .defaults)
        save()
    }

    var todayKey: String {
        UKDayClock.dayKey()
    }

    var isPausedToday: Bool {
        settings.pausedDate == todayKey
    }

    func pauseToday() {
        settings.pausedDate = todayKey
    }

    func resumeToday() {
        settings.pausedDate = nil
        settings.remindersEnabled = true
    }

    func restoreDefaults() {
        settings = .defaults
    }

    func save() {
        JSONFileStore.save(settings, to: fileURL)
    }
}
