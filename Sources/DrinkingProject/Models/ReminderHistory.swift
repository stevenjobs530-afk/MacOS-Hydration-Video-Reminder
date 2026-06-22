import Foundation

struct ReminderHistory: Codable, Equatable {
    var todayKey: String
    var todayReminderCount: Int
    var todayCompletedCount: Int
    var lastReminderAt: Date?
    var lastConfirmationCompletedAt: Date?

    static func empty(todayKey: String) -> ReminderHistory {
        ReminderHistory(
            todayKey: todayKey,
            todayReminderCount: 0,
            todayCompletedCount: 0,
            lastReminderAt: nil,
            lastConfirmationCompletedAt: nil
        )
    }

    private enum CodingKeys: String, CodingKey {
        case todayKey
        case todayReminderCount
        case todayCompletedCount
        case lastReminderAt
        case lastConfirmationCompletedAt
    }

    init(
        todayKey: String,
        todayReminderCount: Int,
        todayCompletedCount: Int,
        lastReminderAt: Date?,
        lastConfirmationCompletedAt: Date?
    ) {
        self.todayKey = todayKey
        self.todayReminderCount = todayReminderCount
        self.todayCompletedCount = todayCompletedCount
        self.lastReminderAt = lastReminderAt
        self.lastConfirmationCompletedAt = lastConfirmationCompletedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        todayKey = try container.decode(String.self, forKey: .todayKey)
        todayReminderCount = try container.decodeIfPresent(Int.self, forKey: .todayReminderCount) ?? 0
        todayCompletedCount = try container.decodeIfPresent(Int.self, forKey: .todayCompletedCount) ?? 0
        lastReminderAt = try container.decodeIfPresent(Date.self, forKey: .lastReminderAt)
        lastConfirmationCompletedAt = try container.decodeIfPresent(Date.self, forKey: .lastConfirmationCompletedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(todayKey, forKey: .todayKey)
        try container.encode(todayReminderCount, forKey: .todayReminderCount)
        try container.encode(todayCompletedCount, forKey: .todayCompletedCount)
        try container.encodeIfPresent(lastReminderAt, forKey: .lastReminderAt)
        try container.encodeIfPresent(lastConfirmationCompletedAt, forKey: .lastConfirmationCompletedAt)
    }
}
