import Foundation

struct ReminderRule: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var startTime: ClockTime
    var endTime: ClockTime
    var intervalMinutes: Int
    var enabled: Bool
    var lockSeconds: Int
    var requiredConfirmations: Int
    var confirmationCooldownSeconds: Int

    static let defaultRule = ReminderRule(
        id: UUID(),
        title: "Default hydration schedule",
        startTime: ClockTime(hour: 8, minute: 0),
        endTime: ClockTime(hour: 22, minute: 0),
        intervalMinutes: 30,
        enabled: true,
        lockSeconds: 30,
        requiredConfirmations: 3,
        confirmationCooldownSeconds: 5
    )

    func matches(date: Date, calendar: Calendar = .current) -> Bool {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        guard let hour = components.hour, let minute = components.minute else { return false }
        let candidate = hour * 60 + minute
        let start = startTime.minutesSinceMidnight
        let end = endTime.minutesSinceMidnight
        let interval = max(1, intervalMinutes)

        let isInRange: Bool
        if start <= end {
            isInRange = candidate >= start && candidate <= end
        } else {
            isInRange = candidate >= start || candidate <= end
        }
        guard isInRange else { return false }

        let offset = (candidate - start + 24 * 60) % (24 * 60)
        return offset % interval == 0
    }
}
