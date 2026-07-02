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
        if controller.shouldTestBackgroundMedia {
            let report = BackgroundMediaControl.enforceBackgroundMediaPause(includeInactiveDiagnostics: true)
            print(report.summaryText)
            Darwin.exit(0)
        }
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
        configureStatusIcon()
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
        configureStatusIcon()
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
        menu.addItem(NSMenuItem(title: "退出 \(controller.paths.variant.displayName)", action: #selector(quitApp), keyEquivalent: "q"))
    }

    private func configureStatusIcon() {
        statusItem.length = NSStatusItem.squareLength
        guard let button = statusItem.button else { return }
        button.title = ""
        button.image = teaCupStatusImage()
        button.imagePosition = .imageOnly
        button.toolTip = "\(controller.paths.variant.displayName) · \(controller.currentStatusText)"
    }

    private func teaCupStatusImage() -> NSImage {
        if let image = NSImage(systemSymbolName: "cup.and.saucer.fill", accessibilityDescription: "Drinking Project") {
            image.isTemplate = true
            return image
        }

        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.lockFocus()
        NSColor.black.setStroke()
        NSColor.black.setFill()

        let cupRect = NSRect(x: 4, y: 6, width: 9, height: 7)
        let cup = NSBezierPath(roundedRect: cupRect, xRadius: 2, yRadius: 2)
        cup.lineWidth = 1.6
        cup.stroke()

        let handle = NSBezierPath()
        handle.move(to: NSPoint(x: 13, y: 11))
        handle.curve(
            to: NSPoint(x: 13, y: 7.5),
            controlPoint1: NSPoint(x: 17, y: 11),
            controlPoint2: NSPoint(x: 17, y: 7.5)
        )
        handle.lineWidth = 1.6
        handle.stroke()

        let saucer = NSBezierPath()
        saucer.move(to: NSPoint(x: 3, y: 4.5))
        saucer.line(to: NSPoint(x: 15, y: 4.5))
        saucer.lineWidth = 1.6
        saucer.stroke()

        image.unlockFocus()
        image.isTemplate = true
        return image
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
        // Match this build's own executable name so each variant only guards against
        // duplicates of itself (e.g. the claude build won't clash with the default build).
        let ownProcessName = ProcessInfo.processInfo.processName
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-x", ownProcessName]

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
