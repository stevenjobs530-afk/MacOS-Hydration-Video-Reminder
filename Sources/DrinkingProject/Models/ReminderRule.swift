import Foundation

/// Preset bundles that map onto a rule's lock / confirmation / cooldown fields.
/// Presets are just convenient starting points; the underlying numbers stay editable.
enum ReminderIntensityPreset: String, CaseIterable, Identifiable {
    case gentle
    case standard
    case strict

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gentle: return "温和"
        case .standard: return "标准"
        case .strict: return "严格"
        }
    }

    var lockSeconds: Int {
        switch self {
        case .gentle: return 10
        case .standard: return 30
        case .strict: return 60
        }
    }

    var requiredConfirmations: Int {
        switch self {
        case .gentle: return 1
        case .standard: return 3
        case .strict: return 5
        }
    }

    var confirmationCooldownSeconds: Int {
        switch self {
        case .gentle: return 1
        case .standard: return 5
        case .strict: return 8
        }
    }
}

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
        return matches(minuteOfDay: hour * 60 + minute)
    }

    func matches(minuteOfDay: Int) -> Bool {
        let candidate = (minuteOfDay % (24 * 60) + 24 * 60) % (24 * 60)
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

    var normalized: ReminderRule {
        var copy = self
        copy.title = copy.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if copy.title.isEmpty {
            copy.title = "未命名提醒规则"
        }
        copy.startTime = copy.startTime.normalized
        copy.endTime = copy.endTime.normalized
        copy.intervalMinutes = min(max(copy.intervalMinutes, 1), 240)
        copy.lockSeconds = min(max(copy.lockSeconds, 0), 300)
        copy.requiredConfirmations = min(max(copy.requiredConfirmations, 1), 10)
        copy.confirmationCooldownSeconds = min(max(copy.confirmationCooldownSeconds, 0), 60)
        return copy
    }

    /// Apply an intensity preset to the lock / confirmation / cooldown fields,
    /// leaving the schedule (time range, interval) untouched.
    mutating func applyIntensity(_ preset: ReminderIntensityPreset) {
        lockSeconds = preset.lockSeconds
        requiredConfirmations = preset.requiredConfirmations
        confirmationCooldownSeconds = preset.confirmationCooldownSeconds
    }

    /// The preset whose values currently match this rule, if any (otherwise it's a custom mix).
    var matchedIntensityPreset: ReminderIntensityPreset? {
        ReminderIntensityPreset.allCases.first {
            $0.lockSeconds == lockSeconds
                && $0.requiredConfirmations == requiredConfirmations
                && $0.confirmationCooldownSeconds == confirmationCooldownSeconds
        }
    }
}
