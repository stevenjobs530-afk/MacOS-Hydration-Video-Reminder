import SwiftUI

struct ReminderRulesView: View {
    @ObservedObject var store: ReminderStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Reminder Rules")
                    .font(.largeTitle.weight(.semibold))
                Spacer()
                Button("Add Rule") {
                    store.addRule()
                }
            }

            ScrollView {
                VStack(spacing: 12) {
                    ForEach($store.rules) { $rule in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                TextField("Rule title", text: $rule.title)
                                    .textFieldStyle(.roundedBorder)
                                Toggle("Enabled", isOn: $rule.enabled)
                                Button("Delete") {
                                    store.deleteRule(id: rule.id)
                                }
                            }

                            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                                GridRow {
                                    timeEditor("Start", time: $rule.startTime)
                                    timeEditor("End", time: $rule.endTime)
                                }
                                GridRow {
                                    Stepper("Every \(rule.intervalMinutes) min", value: $rule.intervalMinutes, in: 1...240)
                                    Stepper("Lock \(rule.lockSeconds)s", value: $rule.lockSeconds, in: 0...300)
                                }
                                GridRow {
                                    Stepper("Confirm \(rule.requiredConfirmations)x", value: $rule.requiredConfirmations, in: 1...10)
                                    Stepper("Cooldown \(rule.confirmationCooldownSeconds)s", value: $rule.confirmationCooldownSeconds, in: 0...60)
                                }
                            }
                            .font(.system(size: 13))
                        }
                        .padding(14)
                        .background(.background)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.18))
                        )
                    }
                }
            }

            Button("Restore Default Rule") {
                store.resetDefaults()
            }
        }
        .padding(28)
    }

    private func timeEditor(_ title: String, time: Binding<ClockTime>) -> some View {
        VStack(alignment: .leading) {
            Text("\(title): \(time.wrappedValue.label)")
                .foregroundStyle(.secondary)
            HStack {
                Stepper("Hour \(time.wrappedValue.hour)", value: time.hour, in: 0...23)
                Stepper("Minute \(time.wrappedValue.minute)", value: time.minute, in: 0...59)
            }
        }
    }
}
