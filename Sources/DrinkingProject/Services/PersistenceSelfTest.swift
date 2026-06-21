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
            && reloadedSettingsStore.isPausedToday
        let historyPersisted = reloadedHistoryStore.history.todayReminderCount == 1
            && reloadedHistoryStore.history.lastReminderAt != nil
            && reloadedHistoryStore.history.lastConfirmationCompletedAt != nil

        let passed = rulePersisted && videoPersisted && settingsPersisted && historyPersisted
        let lines = [
            "[DrinkingProject] self_test_persistence support_dir=\(paths.appSupportDirectory.path)",
            "[DrinkingProject] self_test_persistence rule=\(rulePersisted)",
            "[DrinkingProject] self_test_persistence video=\(videoPersisted)",
            "[DrinkingProject] self_test_persistence settings=\(settingsPersisted)",
            "[DrinkingProject] self_test_persistence history=\(historyPersisted)",
            "[DrinkingProject] self_test_persistence result=\(passed ? "pass" : "fail")"
        ]
        FileHandle.standardOutput.write(Data((lines.joined(separator: "\n") + "\n").utf8))
        return passed
    }
}
