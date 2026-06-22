import Foundation

@MainActor
enum PersistenceSelfTest {
    static func run(paths: AppPaths) -> Bool {
        try? FileManager.default.removeItem(at: paths.appSupportDirectory)
        try? FileManager.default.createDirectory(
            at: paths.appSupportDirectory,
            withIntermediateDirectories: true
        )

        let reminderStore = ReminderStore(paths: paths)
        var rule = ReminderRule.defaultRule
        rule.id = UUID()
        rule.title = "Self-test reminder rule"
        rule.intervalMinutes = 45
        rule.enabled = false
        reminderStore.rules.append(rule)

        let videoStore = VideoLibraryStore(paths: paths)
        videoStore.addReference(url: paths.videoMaterialDirectory)
        if let index = videoStore.items.firstIndex(where: { $0.url.path == paths.videoMaterialDirectory.path }) {
            videoStore.items[index].displayName = "Self-test video folder"
            videoStore.items[index].isEnabled = false
        }

        let settingsStore = SettingsStore(paths: paths)
        settingsStore.settings.playbackMode = .loopSelected
        settingsStore.settings.reminderVolume = 22
        settingsStore.settings.launchAtLoginEnabled = true
        settingsStore.settings.playgroundModeEnabled = true
        settingsStore.pauseToday()

        let historyStore = HistoryStore(paths: paths)
        historyStore.recordReminderShown()
        historyStore.recordConfirmationCompleted()

        let reloadedReminderStore = ReminderStore(paths: paths)
        let reloadedVideoStore = VideoLibraryStore(paths: paths)
        let reloadedSettingsStore = SettingsStore(paths: paths)
        let reloadedHistoryStore = HistoryStore(paths: paths)

        let rulePersisted = reloadedReminderStore.rules.contains {
            $0.id == rule.id
                && $0.title == "Self-test reminder rule"
                && $0.intervalMinutes == 45
                && !$0.enabled
        }
        let videoPersisted = reloadedVideoStore.items.contains {
            $0.displayName == "Self-test video folder"
                && $0.kind == .folder
                && !$0.isEnabled
                && $0.url.path == paths.videoMaterialDirectory.path
        }
        let settingsPersisted = reloadedSettingsStore.settings.playbackMode == .loopSelected
            && Int(reloadedSettingsStore.settings.reminderVolume) == 22
            && reloadedSettingsStore.settings.launchAtLoginEnabled
            && reloadedSettingsStore.settings.playgroundModeEnabled
            && reloadedSettingsStore.isPausedToday
        let historyPersisted = reloadedHistoryStore.history.todayReminderCount == 1
            && reloadedHistoryStore.history.todayCompletedCount == 1
            && reloadedHistoryStore.history.lastReminderAt != nil
            && reloadedHistoryStore.history.lastConfirmationCompletedAt != nil
        let corruptJSONRecovered = verifyCorruptJSONBackup(paths: paths)
        let schedulerRulesPassed = verifySchedulerRuleEdges()
        let playgroundConfigurationPassed = verifyPlaygroundConfiguration()

        let passed = rulePersisted
            && videoPersisted
            && settingsPersisted
            && historyPersisted
            && corruptJSONRecovered
            && schedulerRulesPassed
            && playgroundConfigurationPassed
        let lines = [
            "[DrinkingProject] self_test_persistence support_dir=\(paths.appSupportDirectory.path)",
            "[DrinkingProject] self_test_persistence rule=\(rulePersisted)",
            "[DrinkingProject] self_test_persistence video=\(videoPersisted)",
            "[DrinkingProject] self_test_persistence settings=\(settingsPersisted)",
            "[DrinkingProject] self_test_persistence history=\(historyPersisted)",
            "[DrinkingProject] self_test_persistence corrupt_json_backup=\(corruptJSONRecovered)",
            "[DrinkingProject] self_test_persistence scheduler_edges=\(schedulerRulesPassed)",
            "[DrinkingProject] self_test_persistence playground_manual_only=\(playgroundConfigurationPassed)",
            "[DrinkingProject] self_test_persistence result=\(passed ? "pass" : "fail")"
        ]
        FileHandle.standardOutput.write(Data((lines.joined(separator: "\n") + "\n").utf8))
        return passed
    }

    private static func verifyCorruptJSONBackup(paths: AppPaths) -> Bool {
        let url = paths.appSupportDirectory.appendingPathComponent("corrupt-self-test.json")
        try? Data("{broken json".utf8).write(to: url, options: [.atomic])
        let recovered = JSONFileStore.load([String].self, from: url, fallback: ["fallback"])
        let backupPrefix = "\(url.lastPathComponent).corrupt-"
        let backups = (try? FileManager.default.contentsOfDirectory(
            at: paths.appSupportDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
        return recovered == ["fallback"]
            && backups.contains { $0.lastPathComponent.hasPrefix(backupPrefix) }
    }

    private static func verifySchedulerRuleEdges() -> Bool {
        let defaultRule = ReminderRule.defaultRule
        var overnightRule = ReminderRule.defaultRule
        overnightRule.startTime = ClockTime(hour: 22, minute: 0)
        overnightRule.endTime = ClockTime(hour: 2, minute: 0)
        overnightRule.intervalMinutes = 30

        return defaultRule.matches(minuteOfDay: 8 * 60)
            && defaultRule.matches(minuteOfDay: 22 * 60)
            && !defaultRule.matches(minuteOfDay: 22 * 60 + 30)
            && overnightRule.matches(minuteOfDay: 22 * 60)
            && overnightRule.matches(minuteOfDay: 23 * 60 + 30)
            && overnightRule.matches(minuteOfDay: 1 * 60 + 30)
            && overnightRule.matches(minuteOfDay: 2 * 60)
            && !overnightRule.matches(minuteOfDay: 3 * 60)
    }

    private static func verifyPlaygroundConfiguration() -> Bool {
        let rule = ReminderRule.defaultRule
        let manualPlayground = ReminderConfiguration.make(
            rule: rule,
            playbackMode: .advanceOnEnd,
            isManual: true,
            playgroundModeEnabled: true,
            friendlyMessage: "test"
        )
        let scheduledPlaygroundSetting = ReminderConfiguration.make(
            rule: rule,
            playbackMode: .advanceOnEnd,
            isManual: false,
            playgroundModeEnabled: true,
            friendlyMessage: "test"
        )
        let manualNormal = ReminderConfiguration.make(
            rule: rule,
            playbackMode: .advanceOnEnd,
            isManual: true,
            playgroundModeEnabled: false,
            friendlyMessage: "test"
        )

        return manualPlayground.lockSeconds == 3
            && manualPlayground.requiredConfirmations == 1
            && manualPlayground.confirmationCooldownSeconds == 1
            && manualPlayground.isPlaygroundMode
            && scheduledPlaygroundSetting.lockSeconds == rule.lockSeconds
            && scheduledPlaygroundSetting.requiredConfirmations == rule.requiredConfirmations
            && scheduledPlaygroundSetting.confirmationCooldownSeconds == rule.confirmationCooldownSeconds
            && !scheduledPlaygroundSetting.isPlaygroundMode
            && manualNormal.lockSeconds == rule.lockSeconds
            && manualNormal.requiredConfirmations == rule.requiredConfirmations
            && manualNormal.confirmationCooldownSeconds == rule.confirmationCooldownSeconds
            && !manualNormal.isPlaygroundMode
    }
}
