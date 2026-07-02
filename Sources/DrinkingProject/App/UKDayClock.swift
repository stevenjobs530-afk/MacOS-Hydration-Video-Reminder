import Foundation

enum UKDayClock {
    static let timeZone = TimeZone(identifier: "Europe/London") ?? .current

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_GB")
        calendar.timeZone = timeZone
        return calendar
    }

    static func dayKey(for date: Date = Date()) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    static func startOfNextDay(after date: Date = Date()) -> Date? {
        calendar.dateInterval(of: .day, for: date)?.end
    }
}
