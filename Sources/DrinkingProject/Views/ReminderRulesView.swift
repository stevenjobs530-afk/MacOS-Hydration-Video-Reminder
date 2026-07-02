import SwiftUI

struct ReminderRulesView: View {
    @ObservedObject var controller: AppController
    @ObservedObject var store: ReminderStore

    init(controller: AppController) {
        self.controller = controller
        store = controller.reminderStore
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("提醒规则")
                    .font(.largeTitle.weight(.semibold))
                Spacer()
                Button("新增规则") {
                    store.addRule()
                }
            }

            Text(controller.nextReminderText)
                .foregroundStyle(.secondary)

            if let overlapMessage {
                Label(overlapMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.callout)
            }

            Text("同一分钟如果多个规则同时匹配，只会触发列表中靠前的第一个规则。默认规则按英国时间在 08:00 到 22:00 每 30 分钟触发，包含 22:00，不包含 22:30。")
                .font(.callout)
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(spacing: 12) {
                    ForEach($store.rules) { $rule in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                TextField("规则名称", text: $rule.title)
                                    .textFieldStyle(.roundedBorder)
                                Toggle("启用", isOn: $rule.enabled)
                                Button("删除") {
                                    store.deleteRule(id: rule.id)
                                }
                            }

                            HStack(spacing: 8) {
                                Text("强度预设")
                                    .foregroundStyle(.secondary)
                                ForEach(ReminderIntensityPreset.allCases) { preset in
                                    Button(preset.title) {
                                        var updated = rule
                                        updated.applyIntensity(preset)
                                        $rule.wrappedValue = updated
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(rule.matchedIntensityPreset == preset ? Color.accentColor : Color.secondary)
                                }
                                Text("当前：\(rule.matchedIntensityPreset?.title ?? "自定义")")
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .font(.system(size: 13))

                            Text("预设只调整锁定、确认次数、冷却三项；时间段和间隔不变，仍可在下面手动微调。")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                                GridRow {
                                    timeEditor("开始", time: $rule.startTime)
                                    timeEditor("结束", time: $rule.endTime)
                                }
                                GridRow {
                                    Stepper("每 \(rule.intervalMinutes) 分钟", value: $rule.intervalMinutes, in: 1...240)
                                    Stepper("锁定 \(rule.lockSeconds) 秒", value: $rule.lockSeconds, in: 0...300)
                                }
                                GridRow {
                                    Stepper("确认 \(rule.requiredConfirmations) 次", value: $rule.requiredConfirmations, in: 1...10)
                                    Stepper("冷却 \(rule.confirmationCooldownSeconds) 秒", value: $rule.confirmationCooldownSeconds, in: 0...60)
                                }
                            }
                            .font(.system(size: 13))

                            ForEach(warnings(for: rule), id: \.self) { warning in
                                Text(warning)
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
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

            Button("恢复默认规则") {
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
                Stepper("小时 \(time.wrappedValue.hour)", value: time.hour, in: 0...23)
                Stepper("分钟 \(time.wrappedValue.minute)", value: time.minute, in: 0...59)
            }
        }
    }

    private var overlapMessage: String? {
        let enabledRules = store.rules.filter(\.enabled)
        for firstIndex in enabledRules.indices {
            for secondIndex in enabledRules.indices where secondIndex > firstIndex {
                if rulesOverlap(enabledRules[firstIndex], enabledRules[secondIndex]) {
                    return "有提醒规则时间重叠；重叠时会按列表顺序触发第一个匹配规则。"
                }
            }
        }
        return nil
    }

    private func warnings(for rule: ReminderRule) -> [String] {
        var messages: [String] = []
        if rule.startTime.minutesSinceMidnight == rule.endTime.minutesSinceMidnight {
            messages.append("开始和结束时间相同：这个规则只会在 \(rule.startTime.label) 这一分钟触发。")
        } else if rule.startTime.minutesSinceMidnight > rule.endTime.minutesSinceMidnight {
            messages.append("跨夜规则：会从 \(rule.startTime.label) 持续到第二天 \(rule.endTime.label)。")
        }
        if rule.intervalMinutes < 5 {
            messages.append("提醒间隔小于 5 分钟，可能过于频繁。")
        }
        return messages
    }

    private func rulesOverlap(_ first: ReminderRule, _ second: ReminderRule) -> Bool {
        for minute in 0..<(24 * 60) {
            if first.matches(minuteOfDay: minute), second.matches(minuteOfDay: minute) {
                return true
            }
        }
        return false
    }
}
