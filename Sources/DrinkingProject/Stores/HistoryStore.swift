import Combine
import Foundation

@MainActor
final class HistoryStore: ObservableObject {
    @Published var history: ReminderHistory {
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
        fileURL = paths.appSupportDirectory.appendingPathComponent("history.json")
        let today = dateFormatter.string(from: Date())
        history = JSONFileStore.load(ReminderHistory.self, from: fileURL, fallback: .empty(todayKey: today))
        rolloverIfNeeded()
        save()
    }

    func recordReminderShown() {
        rolloverIfNeeded()
        history.todayReminderCount += 1
        history.lastReminderAt = Date()
    }

    func recordConfirmationCompleted() {
        rolloverIfNeeded()
        history.lastConfirmationCompletedAt = Date()
    }

    private func rolloverIfNeeded() {
        let today = dateFormatter.string(from: Date())
        if history.todayKey != today {
            history = .empty(todayKey: today)
        }
    }

    func save() {
        JSONFileStore.save(history, to: fileURL)
    }
}
