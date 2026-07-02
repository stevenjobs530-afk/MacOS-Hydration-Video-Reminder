import Combine
import Foundation

@MainActor
final class HistoryStore: ObservableObject {
    @Published var history: ReminderHistory {
        didSet { save() }
    }

    private let fileURL: URL
    private var rolloverTimer: Timer?

    init(paths: AppPaths) {
        fileURL = paths.appSupportDirectory.appendingPathComponent("history.json")
        let today = UKDayClock.dayKey()
        history = JSONFileStore.load(ReminderHistory.self, from: fileURL, fallback: .empty(todayKey: today))
        rolloverIfNeeded()
        save()
        scheduleNextRollover()
    }

    func recordReminderShown() {
        rolloverIfNeeded()
        history.todayReminderCount += 1
        history.lastReminderAt = Date()
    }

    func recordConfirmationCompleted() {
        rolloverIfNeeded()
        history.todayCompletedCount += 1
        history.lastConfirmationCompletedAt = Date()
    }

    private func rolloverIfNeeded() {
        let today = UKDayClock.dayKey()
        if history.todayKey != today {
            history = .empty(todayKey: today)
        }
    }

    private func scheduleNextRollover() {
        rolloverTimer?.invalidate()
        guard let nextMidnight = UKDayClock.startOfNextDay() else { return }
        let timer = Timer(fire: nextMidnight.addingTimeInterval(0.5), interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.rolloverAtUKMidnight()
            }
        }
        rolloverTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func rolloverAtUKMidnight() {
        rolloverIfNeeded()
        save()
        scheduleNextRollover()
    }

    func save() {
        JSONFileStore.save(history, to: fileURL)
    }
}
