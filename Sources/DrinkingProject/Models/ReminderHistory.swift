import Foundation

struct ReminderHistory: Codable, Equatable {
    var todayKey: String
    var todayReminderCount: Int
    var lastReminderAt: Date?
    var lastConfirmationCompletedAt: Date?

    static func empty(todayKey: String) -> ReminderHistory {
        ReminderHistory(
            todayKey: todayKey,
            todayReminderCount: 0,
            lastReminderAt: nil,
            lastConfirmationCompletedAt: nil
        )
    }
}
