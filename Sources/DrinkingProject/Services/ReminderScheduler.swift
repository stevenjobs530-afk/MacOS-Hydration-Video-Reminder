import Foundation

@MainActor
final class ReminderScheduler {
    private let ruleProvider: () -> [ReminderRule]
    private let canFire: () -> Bool
    private let fire: (ReminderRule) -> Void
    private var timer: Timer?
    private var firedSlotKeys = Set<String>()

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
        for offset in 0..<(60 * 24 * 2) {
            guard let candidate = calendar.date(byAdding: .minute, value: offset, to: date) else {
                continue
            }
            if rules.contains(where: { $0.matches(date: candidate, calendar: calendar) }) {
                return candidate
            }
        }
        return nil
    }

    private func checkSchedule() {
        guard canFire() else { return }
        let now = Date()
        let calendar = Calendar.current
        for rule in ruleProvider() where rule.enabled && rule.matches(date: now, calendar: calendar) {
            let key = slotKey(for: now, rule: rule, calendar: calendar)
            guard !firedSlotKeys.contains(key) else { continue }
            firedSlotKeys.insert(key)
            fire(rule)
            break
        }
    }

    private func slotKey(for date: Date, rule: ReminderRule, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return "\(rule.id.uuidString)-\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)-\(components.hour ?? 0)-\(components.minute ?? 0)"
    }
}
