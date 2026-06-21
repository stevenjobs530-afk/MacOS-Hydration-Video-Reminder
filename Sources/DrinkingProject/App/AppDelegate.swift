import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let controller = AppController.shared
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        controller.applyLaunchArguments()
        configureStatusMenu()
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
        statusItem.button?.title = "水"
        statusItem.button?.toolTip = "Drinking Project"
        menu.delegate = self
        statusItem.menu = menu
        rebuildMenu()
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        let stateItem = NSMenuItem(title: controller.currentStatusText, action: nil, keyEquivalent: "")
        stateItem.isEnabled = false
        menu.addItem(stateItem)

        let nextItem = NSMenuItem(title: controller.nextReminderText, action: nil, keyEquivalent: "")
        nextItem.isEnabled = false
        menu.addItem(nextItem)
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
}
