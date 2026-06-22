import Foundation

struct ClockTime: Codable, Hashable, Comparable {
    var hour: Int
    var minute: Int

    var minutesSinceMidnight: Int {
        max(0, min(23, hour)) * 60 + max(0, min(59, minute))
    }

    var label: String {
        String(format: "%02d:%02d", max(0, min(23, hour)), max(0, min(59, minute)))
    }

    var normalized: ClockTime {
        ClockTime(
            hour: min(max(hour, 0), 23),
            minute: min(max(minute, 0), 59)
        )
    }

    static func < (lhs: ClockTime, rhs: ClockTime) -> Bool {
        lhs.minutesSinceMidnight < rhs.minutesSinceMidnight
    }
}
