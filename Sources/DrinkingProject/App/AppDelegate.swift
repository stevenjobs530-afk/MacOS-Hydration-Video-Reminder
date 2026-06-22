import AppKit
import Combine
import Darwin

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let controller = AppController.shared
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        controller.applyLaunchArguments()
        if !controller.shouldRunPersistenceSelfTest, anotherInstanceIsRunning() {
            Darwin.exit(0)
        }
        if controller.shouldRunPersistenceSelfTest {
            let passed = PersistenceSelfTest.run(paths: controller.paths)
            NSApp.terminate(passed ? nil : self)
            Darwin.exit(passed ? 0 : 1)
        }
        configureStatusMenu()
        observeController()
        controller.startScheduler()

        if controller.shouldTestOnLaunch {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.controller.showTestReminder()
            }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        controller.stopScheduler()
        return .terminateNow
    }

    private func configureStatusMenu() {
        statusItem.button?.title = controller.statusItemTitle
        statusItem.button?.toolTip = "Drinking Project"
        menu.delegate = self
        statusItem.menu = menu
        rebuildMenu()
    }

    private func observeController() {
        controller.$activeReminder
            .sink { [weak self] _ in
                self?.rebuildMenu()
            }
            .store(in: &cancellables)

        controller.settingsStore.$settings
            .sink { [weak self] _ in
                self?.rebuildMenu()
            }
            .store(in: &cancellables)
    }

    func menuWillOpen(_ menu: NSMenu) {
        controller.scanVideos()
        rebuildMenu()
    }

    private func rebuildMenu() {
        statusItem.button?.title = controller.statusItemTitle
        menu.removeAllItems()

        let stateItem = NSMenuItem(title: "当前状态：\(controller.currentStatusText)", action: nil, keyEquivalent: "")
        stateItem.isEnabled = false
        menu.addItem(stateItem)

        let nextItem = NSMenuItem(title: controller.nextReminderText, action: nil, keyEquivalent: "")
        nextItem.isEnabled = false
        menu.addItem(nextItem)

        let videoItem = NSMenuItem(title: "可播放视频：\(controller.playableVideoCount)", action: nil, keyEquivalent: "")
        videoItem.isEnabled = false
        menu.addItem(videoItem)
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "打开管理窗口", action: #selector(openManagementWindow), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "开启提醒", action: #selector(enableReminders), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "今日暂停", action: #selector(pauseToday), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "重新开启今日提醒", action: #selector(resumeToday), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "手动测试提醒窗口", action: #selector(testReminder), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出 Drinking Project", action: #selector(quitApp), keyEquivalent: "q"))
    }

    @objc private func openManagementWindow() {
        controller.presentManagementWindow()
    }

    @objc private func enableReminders() {
        controller.enableReminders()
        rebuildMenu()
    }

    @objc private func pauseToday() {
        controller.pauseToday()
        rebuildMenu()
    }

    @objc private func resumeToday() {
        controller.resumeToday()
        rebuildMenu()
    }

    @objc private func testReminder() {
        controller.showTestReminder()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func anotherInstanceIsRunning() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-x", "DrinkingProject"]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return false
        }

        let currentPID = ProcessInfo.processInfo.processIdentifier
        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return output
            .split(whereSeparator: \.isNewline)
            .compactMap { pid_t($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .contains { $0 != currentPID }
    }
}
