import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class AppController: ObservableObject {
    static let shared = AppController()

    let paths: AppPaths
    let reminderStore: ReminderStore
    let videoLibraryStore: VideoLibraryStore
    let settingsStore: SettingsStore
    let historyStore: HistoryStore
    let videoScanner: VideoScanner

    @Published private(set) var activeReminder: ReminderWindowController?
    private var managementWindow: NSWindow?
    private lazy var scheduler = ReminderScheduler(
        ruleProvider: { [weak self] in
            self?.reminderStore.rules ?? []
        },
        canFire: { [weak self] in
            self?.canFireScheduledReminder ?? false
        },
        fire: { [weak self] rule in
            self?.showReminder(for: rule, isManual: false)
        }
    )

    private(set) var shouldTestOnLaunch = false
    private(set) var shouldRunPersistenceSelfTest = false

    private init() {
        paths = AppPaths(arguments: CommandLine.arguments)
        reminderStore = ReminderStore(paths: paths)
        videoLibraryStore = VideoLibraryStore(paths: paths)
        settingsStore = SettingsStore(paths: paths)
        historyStore = HistoryStore(paths: paths)
        videoScanner = VideoScanner(paths: paths, libraryStore: videoLibraryStore)
    }

    func applyLaunchArguments() {
        let arguments = Set(CommandLine.arguments.dropFirst())
        shouldTestOnLaunch = arguments.contains("--test-on-launch")
        shouldRunPersistenceSelfTest = arguments.contains("--self-test-persistence")
        if arguments.contains("--resume-on-launch") {
            resumeToday()
        }
    }

    func startScheduler() {
        scheduler.start()
    }

    func stopScheduler() {
        scheduler.stop()
        activeReminder = nil
    }

    var currentStatusText: String {
        if !settingsStore.settings.remindersEnabled {
            return "状态：提醒已关闭"
        }
        if settingsStore.isPausedToday {
            return "状态：今日已暂停"
        }
        return "状态：提醒运行中"
    }

    var nextReminderText: String {
        guard settingsStore.settings.remindersEnabled, !settingsStore.isPausedToday else {
            return "下次提醒：暂无"
        }
        guard let nextDate = scheduler.nextReminderDate(after: Date()) else {
            return "下次提醒：暂无"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return "下次提醒：\(formatter.string(from: nextDate))"
    }

    var nextReminderDate: Date? {
        guard settingsStore.settings.remindersEnabled, !settingsStore.isPausedToday else { return nil }
        return scheduler.nextReminderDate(after: Date())
    }

    func enableReminders() {
        settingsStore.settings.remindersEnabled = true
    }

    func pauseToday() {
        settingsStore.pauseToday()
    }

    func resumeToday() {
        settingsStore.resumeToday()
    }

    func scanVideos() {
        _ = videoScanner.scanVideos()
    }

    func showTestReminder() {
        let rule = reminderStore.rules.first(where: \.enabled) ?? .defaultRule
        showReminder(for: rule, isManual: true)
    }

    func presentManagementWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let existing = NSApp.windows.first(where: { $0.title == "Drinking Project" }) {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        if let managementWindow {
            managementWindow.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Drinking Project"
        window.center()
        window.contentView = NSHostingView(rootView: ContentView(controller: self))
        managementWindow = window
        window.makeKeyAndOrderFront(nil)
    }

    private var canFireScheduledReminder: Bool {
        settingsStore.settings.remindersEnabled
            && !settingsStore.isPausedToday
            && activeReminder == nil
    }

    private func showReminder(for rule: ReminderRule, isManual: Bool) {
        guard activeReminder == nil else { return }
        let logLine = "[DrinkingProject] reminder_presenting manual=\(isManual) rule_id=\(rule.id.uuidString)\n"
        FileHandle.standardOutput.write(Data(logLine.utf8))
        BackgroundMediaControl.pauseLikelyMediaSources()
        SystemAudio.setOutputVolume(to: Int(settingsStore.settings.reminderVolume))

        let configuration = ReminderConfiguration(
            lockSeconds: rule.lockSeconds,
            requiredConfirmations: rule.requiredConfirmations,
            confirmationCooldownSeconds: rule.confirmationCooldownSeconds,
            playbackMode: settingsStore.settings.playbackMode
        )
        let reminder = ReminderWindowController(
            videoURL: videoScanner.nextPlayableVideoURL(),
            videoScanner: videoScanner,
            settingsStore: settingsStore,
            configuration: configuration,
            webResourceDirectory: paths.webResourceDirectory
        )
        activeReminder = reminder
        historyStore.recordReminderShown()
        reminder.onCompleted = { [weak self] in
            self?.historyStore.recordConfirmationCompleted()
        }
        reminder.onClosed = { [weak self] in
            self?.activeReminder = nil
        }
        reminder.present()
    }
}
