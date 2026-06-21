import Combine
import Foundation

@MainActor
final class ReminderStore: ObservableObject {
    @Published var rules: [ReminderRule] {
        didSet { save() }
    }

    private let fileURL: URL

    init(paths: AppPaths) {
        fileURL = paths.appSupportDirectory.appendingPathComponent("reminder-rules.json")
        let loaded = JSONFileStore.load([ReminderRule].self, from: fileURL, fallback: [ReminderRule.defaultRule])
        rules = loaded.isEmpty ? [ReminderRule.defaultRule] : loaded
        save()
    }

    func addRule() {
        var newRule = ReminderRule.defaultRule
        newRule.id = UUID()
        newRule.title = "New reminder rule"
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
}
