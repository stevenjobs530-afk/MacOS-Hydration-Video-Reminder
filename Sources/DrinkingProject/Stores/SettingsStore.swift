import Combine
import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings {
        didSet { save() }
    }

    private let fileURL: URL
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    init(paths: AppPaths) {
        fileURL = paths.appSupportDirectory.appendingPathComponent("settings.json")
        settings = JSONFileStore.load(AppSettings.self, from: fileURL, fallback: .defaults)
        save()
    }

    var todayKey: String {
        dateFormatter.string(from: Date())
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
