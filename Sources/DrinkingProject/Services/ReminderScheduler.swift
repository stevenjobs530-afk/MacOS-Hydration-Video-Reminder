import Foundation

@MainActor
final class ReminderScheduler {
    private let ruleProvider: () -> [ReminderRule]
    private let canFire: () -> Bool
    private let fire: (ReminderRule) -> Void
    private var timer: Timer?
    private var firedSlotKeys = Set<String>()
    private var firedSlotDayPrefix: String?

    init(
        ruleProvider: @escaping () -> [ReminderRule],
        canFire: @escaping () -> Bool,
        fire: @escaping (ReminderRule) -> Void
    ) {
        self.ruleProvider = ruleProvider
        self.canFire = canFire
        self.fire = fire
    }

    func start() {
        stop()
        let timer = Timer(timeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkSchedule()
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        checkSchedule()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func nextReminderDate(after date: Date) -> Date? {
        let rules = ruleProvider().filter(\.enabled)
        guard !rules.isEmpty else { return nil }
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .minute, for: date)?.start ?? date
        for offset in 0..<(60 * 24 * 2) {
            guard let candidate = calendar.date(byAdding: .minute, value: offset, to: start) else {
                continue
            }
            let key = slotKey(for: candidate, calendar: calendar)
            if !firedSlotKeys.contains(key), rules.contains(where: { $0.matches(date: candidate, calendar: calendar) }) {
                return candidate
            }
        }
        return nil
    }

    private func checkSchedule() {
        guard canFire() else { return }
        let now = Date()
        let calendar = Calendar.current
        compactOldFiredSlotKeys(now: now, calendar: calendar)
        let key = slotKey(for: now, calendar: calendar)
        guard !firedSlotKeys.contains(key) else { return }

        if let rule = ruleProvider().first(where: { $0.enabled && $0.matches(date: now, calendar: calendar) }) {
            firedSlotKeys.insert(key)
            fire(rule)
        }
    }

    private func compactOldFiredSlotKeys(now: Date, calendar: Calendar) {
        let prefix = dayPrefix(for: now, calendar: calendar)
        guard firedSlotDayPrefix != prefix else { return }
        firedSlotKeys = firedSlotKeys.filter { $0.hasPrefix(prefix) }
        firedSlotDayPrefix = prefix
    }

    private func slotKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return "\(dayPrefix(for: date, calendar: calendar))\(components.hour ?? 0)-\(components.minute ?? 0)"
    }

    private func dayPrefix(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)-"
    }
}
