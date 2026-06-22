import Combine
import Foundation

@MainActor
final class ReminderStore: ObservableObject {
    @Published var rules: [ReminderRule] {
        didSet {
            guard !isApplyingNormalizedRules else {
                save()
                return
            }
            normalizeRulesIfNeeded()
            save()
        }
    }

    private let fileURL: URL
    private var isApplyingNormalizedRules = false

    init(paths: AppPaths) {
        fileURL = paths.appSupportDirectory.appendingPathComponent("reminder-rules.json")
        let loaded = JSONFileStore.load([ReminderRule].self, from: fileURL, fallback: [ReminderRule.defaultRule])
        rules = (loaded.isEmpty ? [ReminderRule.defaultRule] : loaded).map(\.normalized)
        save()
    }

    func addRule() {
        var newRule = ReminderRule.defaultRule
        newRule.id = UUID()
        newRule.title = "新的喝水提醒"
        rules.append(newRule)
    }

    func deleteRule(id: UUID) {
        rules.removeAll { $0.id == id }
        if rules.isEmpty {
            rules = [ReminderRule.defaultRule]
        }
    }

    func resetDefaults() {
        rules = [ReminderRule.defaultRule]
    }

    func save() {
        JSONFileStore.save(rules, to: fileURL)
    }

    private func normalizeRulesIfNeeded() {
        let normalized = rules.map(\.normalized)
        guard normalized != rules else { return }
        isApplyingNormalizedRules = true
        rules = normalized
        isApplyingNormalizedRules = false
    }
}
