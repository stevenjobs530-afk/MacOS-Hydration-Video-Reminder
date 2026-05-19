import AppKit
import AVFoundation
import AVKit
import IOKit

private let projectDirectory = URL(
    fileURLWithPath: FileManager.default.currentDirectoryPath,
    isDirectory: true
)
private let videoDirectory = projectDirectory.appendingPathComponent("视频", isDirectory: true)

private enum DefaultsKey {
    static let remindersEnabled = "remindersEnabled"
    static let pausedDate = "pausedDate"
}

private final class ReminderSettings {
    private let defaults = UserDefaults.standard
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    var remindersEnabled: Bool {
        get {
            if defaults.object(forKey: DefaultsKey.remindersEnabled) == nil {
                return true
            }
            return defaults.bool(forKey: DefaultsKey.remindersEnabled)
        }
        set {
            defaults.set(newValue, forKey: DefaultsKey.remindersEnabled)
        }
    }

    var todayKey: String {
        dateFormatter.string(from: Date())
    }

    var isPausedToday: Bool {
        defaults.string(forKey: DefaultsKey.pausedDate) == todayKey
    }

    func pauseToday() {
        defaults.set(todayKey, forKey: DefaultsKey.pausedDate)
    }

    func resumeToday() {
        defaults.removeObject(forKey: DefaultsKey.pausedDate)
        remindersEnabled = true
    }
}

private final class VideoScanner {
    static func randomPlayableVideoURL() -> URL? {
        let allowedExtensions = Set(["mp4", "mov", "m4v"])
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: videoDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let candidates = files
            .filter { url in
                !url.lastPathComponent.hasPrefix("._")
                    && allowedExtensions.contains(url.pathExtension.lowercased())
                    && ((try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false)
            }
            .sorted {
                $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
            }

        let playableVideos = candidates.filter { url in
            AVURLAsset(url: url).isPlayable
        }

        return playableVideos.randomElement()
    }
}

private enum SystemAudio {
    static func setOutputVolumeToReminderLevel() {
        let script = "set volume output volume 15"
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }
}

private enum BackgroundMediaControl {
    static func pauseLikelyMediaSources() {
        pauseCurrentMediaSessionIfNeeded()
        pauseBrowserMedia()
        pauseKnownPlayerApps()
    }

    private static func pauseBrowserMedia() {
        let pauseScript = "document.querySelectorAll('video,audio').forEach(function(media){ try { media.pause(); } catch (e) {} });"
        let browsers = [
            ("Safari", "do JavaScript \"\(pauseScript)\" in browserTab"),
            ("Google Chrome", "execute browserTab javascript \"\(pauseScript)\""),
            ("Microsoft Edge", "execute browserTab javascript \"\(pauseScript)\""),
            ("Brave Browser", "execute browserTab javascript \"\(pauseScript)\"")
        ]

        for (appName, command) in browsers {
            guard isRunning(appName) else { continue }
            runAppleScript("""
            tell application "\(appName)"
                repeat with browserWindow in windows
                    repeat with browserTab in tabs of browserWindow
                        try
                            \(command)
                        end try
                    end repeat
                end repeat
            end tell
            """)
        }
    }

    private static func pauseKnownPlayerApps() {
        let scriptsByAppName = [
            "Music": #"tell application "Music" to pause"#,
            "Spotify": #"tell application "Spotify" to pause"#,
            "Podcasts": #"tell application "Podcasts" to pause"#,
            "QuickTime Player": #"tell application "QuickTime Player" to pause every document"#,
            "IINA": #"tell application "IINA" to pause"#,
            "VLC": #"tell application "VLC" to pause"#,
            "网易云音乐": #"tell application "网易云音乐" to pause"#,
            "NetEaseMusic": #"tell application "NetEaseMusic" to pause"#,
            "NeteaseMusic": #"tell application "NeteaseMusic" to pause"#,
            "NetEase Cloud Music": #"tell application "NetEase Cloud Music" to pause"#
        ]

        for (appName, script) in scriptsByAppName where isRunning(appName) {
            runAppleScript(script)
        }
    }

    private static func pauseCurrentMediaSessionIfNeeded() {
        let mediaAppNames = [
            "网易云音乐",
            "NetEaseMusic",
            "NeteaseMusic",
            "NetEase Cloud Music"
        ]
        if mediaAppNames.contains(where: isRunning) {
            sendPlayPauseMediaKey()
        }
    }

    private static func isRunning(_ appName: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains { app in
            app.localizedName == appName
        }
    }

    private static func sendPlayPauseMediaKey() {
        postMediaKey(key: NX_KEYTYPE_PLAY, isKeyDown: true)
        postMediaKey(key: NX_KEYTYPE_PLAY, isKeyDown: false)
    }

    private static func postMediaKey(key: Int32, isKeyDown: Bool) {
        let keyState = isKeyDown ? 0xA : 0xB
        let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(keyState << 8)),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: Int16(NX_SUBTYPE_AUX_CONTROL_BUTTONS),
            data1: Int((key << 16) | Int32(keyState << 8)),
            data2: -1
        )
        event?.cgEvent?.post(tap: .cghidEventTap)
    }

    private static func runAppleScript(_ source: String) {
        guard let appleScript = NSAppleScript(source: source) else { return }
        var error: NSDictionary?
        appleScript.executeAndReturnError(&error)
    }
}

private final class ReminderWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "q" {
            NSApp.terminate(nil)
            return
        }
        if event.keyCode == 53 || event.modifierFlags.contains(.command) {
            return
        }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "q" {
            NSApp.terminate(nil)
            return true
        }
        if event.keyCode == 53 || event.modifierFlags.contains(.command) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

private final class ReminderWindowController: NSWindowController, NSWindowDelegate {
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var secondaryWindows: [ReminderWindow] = []
    private var secondaryPlayers: [AVQueuePlayer] = []
    private var secondaryLoopers: [AVPlayerLooper] = []
    private var secondaryProgressLabels: [NSTextField] = []
    private var unlockTimer: Timer?
    private var clickCooldownTimer: Timer?
    private var remainingLockSeconds = 30
    private var confirmationCount = 0
    private var lastConfirmationDate: Date?
    private var mayClose = false

    private let messageLabel = NSTextField(labelWithString: "休息一下，喝点水，保护眼睛。")
    private let progressLabel = NSTextField(labelWithString: "已确认 0/3")
    private let lockLabel = NSTextField(labelWithString: "30 秒后可确认")
    private let confirmButton = NSButton(title: "已饮水", target: nil, action: nil)

    var onClosed: (() -> Void)?

    init(videoURL: URL?) {
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let window = ReminderWindow(
            contentRect: screenFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .screenSaver
        window.backgroundColor = .black
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        buildInterface(videoURL: videoURL)
        buildSecondaryScreenWindows(videoURL: videoURL)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func present() {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.setFrame(NSScreen.main?.frame ?? window.frame, display: true)
        for secondaryWindow in secondaryWindows {
            secondaryWindow.orderFrontRegardless()
        }
        window.makeKeyAndOrderFront(nil)
        startLockCountdown()
        player?.play()
        secondaryPlayers.forEach { $0.play() }
    }

    func forceCloseFromConfirmation() {
        mayClose = true
        cleanup()
        close()
        onClosed?()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        mayClose
    }

    func windowWillClose(_ notification: Notification) {
        cleanup()
    }

    private func buildInterface(videoURL: URL?) {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.black.cgColor

        if let videoURL {
            let item = AVPlayerItem(url: videoURL)
            let queuePlayer = AVQueuePlayer(playerItem: item)
            queuePlayer.isMuted = false
            queuePlayer.volume = 1.0
            queuePlayer.actionAtItemEnd = .none
            player = queuePlayer
            looper = AVPlayerLooper(player: queuePlayer, templateItem: item)

            addCenteredPlayerView(player: queuePlayer, videoURL: videoURL, to: contentView)
        }

        let dimView = NSView()
        dimView.wantsLayer = true
        dimView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.36).cgColor
        dimView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(dimView)
        NSLayoutConstraint.activate([
            dimView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            dimView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            dimView.topAnchor.constraint(equalTo: contentView.topAnchor),
            dimView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 22
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        configureLabels()
        configureButton()

        stack.addArrangedSubview(messageLabel)
        stack.addArrangedSubview(progressLabel)
        stack.addArrangedSubview(lockLabel)
        stack.addArrangedSubview(confirmButton)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 36),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -36),
            confirmButton.widthAnchor.constraint(equalToConstant: 180),
            confirmButton.heightAnchor.constraint(equalToConstant: 52)
        ])
    }

    private func configureLabels() {
        messageLabel.font = NSFont.systemFont(ofSize: 38, weight: .semibold)
        messageLabel.textColor = .white
        messageLabel.alignment = .center
        messageLabel.maximumNumberOfLines = 2
        messageLabel.lineBreakMode = .byWordWrapping

        progressLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 22, weight: .medium)
        progressLabel.textColor = .white
        progressLabel.alignment = .center

        lockLabel.font = NSFont.systemFont(ofSize: 18, weight: .regular)
        lockLabel.textColor = NSColor.white.withAlphaComponent(0.9)
        lockLabel.alignment = .center
    }

    private func buildSecondaryScreenWindows(videoURL: URL?) {
        let mainFrame = NSScreen.main?.frame
        let secondaryScreens = NSScreen.screens.filter { screen in
            guard let mainFrame else { return true }
            return screen.frame != mainFrame
        }

        for screen in secondaryScreens {
            let secondaryWindow = ReminderWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            secondaryWindow.level = .screenSaver
            secondaryWindow.backgroundColor = .black
            secondaryWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            secondaryWindow.isReleasedWhenClosed = false
            secondaryWindow.delegate = self

            let contentView = NSView(frame: screen.frame)
            contentView.wantsLayer = true
            contentView.layer?.backgroundColor = NSColor.black.cgColor
            secondaryWindow.contentView = contentView

            if let videoURL {
                let item = AVPlayerItem(url: videoURL)
                let queuePlayer = AVQueuePlayer(playerItem: item)
                queuePlayer.isMuted = true
                queuePlayer.volume = 0
                queuePlayer.actionAtItemEnd = .none
                let looper = AVPlayerLooper(player: queuePlayer, templateItem: item)

                addCenteredPlayerView(player: queuePlayer, videoURL: videoURL, to: contentView)

                secondaryPlayers.append(queuePlayer)
                secondaryLoopers.append(looper)
            }

            let dimView = NSView()
            dimView.wantsLayer = true
            dimView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.36).cgColor
            dimView.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(dimView)
            NSLayoutConstraint.activate([
                dimView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                dimView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                dimView.topAnchor.constraint(equalTo: contentView.topAnchor),
                dimView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
            ])

            let stack = NSStackView()
            stack.orientation = .vertical
            stack.alignment = .centerX
            stack.spacing = 22
            stack.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(stack)

            let messageLabel = NSTextField(labelWithString: "休息一下，喝点水，保护眼睛。")
            messageLabel.font = NSFont.systemFont(ofSize: 38, weight: .semibold)
            messageLabel.textColor = .white
            messageLabel.alignment = .center
            messageLabel.maximumNumberOfLines = 2
            messageLabel.lineBreakMode = .byWordWrapping

            let progressLabel = NSTextField(labelWithString: "已确认 0/3")
            progressLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 22, weight: .medium)
            progressLabel.textColor = .white
            progressLabel.alignment = .center
            secondaryProgressLabels.append(progressLabel)

            let hintLabel = NSTextField(labelWithString: "请在主屏幕完成确认")
            hintLabel.font = NSFont.systemFont(ofSize: 18, weight: .regular)
            hintLabel.textColor = NSColor.white.withAlphaComponent(0.9)
            hintLabel.alignment = .center

            stack.addArrangedSubview(messageLabel)
            stack.addArrangedSubview(progressLabel)
            stack.addArrangedSubview(hintLabel)

            NSLayoutConstraint.activate([
                stack.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
                stack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
                stack.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 36),
                stack.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -36)
            ])

            secondaryWindows.append(secondaryWindow)
        }
    }

    private func addCenteredPlayerView(player: AVQueuePlayer, videoURL: URL, to contentView: NSView) {
        let playerView = AVPlayerView()
        playerView.player = player
        playerView.controlsStyle = .none
        playerView.videoGravity = .resizeAspect
        playerView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(playerView)

        let displaySize = centeredVideoDisplaySize(for: videoURL, in: contentView.bounds.size)
        NSLayoutConstraint.activate([
            playerView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            playerView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            playerView.widthAnchor.constraint(equalToConstant: displaySize.width),
            playerView.heightAnchor.constraint(equalToConstant: displaySize.height)
        ])
    }

    private func centeredVideoDisplaySize(for videoURL: URL, in containerSize: CGSize) -> CGSize {
        let naturalSize = naturalVideoSize(for: videoURL) ?? CGSize(width: 960, height: 540)
        guard naturalSize.width > 0, naturalSize.height > 0 else {
            return CGSize(width: min(960, containerSize.width * 0.9), height: min(540, containerSize.height * 0.8))
        }

        let maxWidth = max(240, containerSize.width * 0.92)
        let maxHeight = max(180, containerSize.height * 0.82)
        let scale = min(1, maxWidth / naturalSize.width, maxHeight / naturalSize.height)
        return CGSize(width: naturalSize.width * scale, height: naturalSize.height * scale)
    }

    private func naturalVideoSize(for videoURL: URL) -> CGSize? {
        let asset = AVURLAsset(url: videoURL)
        guard let track = asset.tracks(withMediaType: .video).first else { return nil }
        let transformedSize = track.naturalSize.applying(track.preferredTransform)
        let width = abs(transformedSize.width)
        let height = abs(transformedSize.height)
        guard width > 0, height > 0 else { return nil }
        return CGSize(width: width, height: height)
    }

    private func configureButton() {
        confirmButton.target = self
        confirmButton.action = #selector(confirmWater)
        confirmButton.isEnabled = false
        confirmButton.isHidden = true
        confirmButton.bezelStyle = .rounded
        confirmButton.font = NSFont.systemFont(ofSize: 20, weight: .semibold)
    }

    private func startLockCountdown() {
        remainingLockSeconds = 30
        lockLabel.stringValue = "30 秒后可确认"
        confirmButton.isHidden = true
        confirmButton.isEnabled = false

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] timer in
            guard let self else { return }
            remainingLockSeconds -= 1
            if remainingLockSeconds > 0 {
                lockLabel.stringValue = "\(remainingLockSeconds) 秒后可确认"
            } else {
                timer.invalidate()
                unlockTimer = nil
                lockLabel.stringValue = "请点击 3 次，每次间隔至少 5 秒"
                confirmButton.isHidden = false
                confirmButton.isEnabled = true
            }
        }
        unlockTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    @objc private func confirmWater() {
        let now = Date()
        if let lastConfirmationDate {
            let elapsed = now.timeIntervalSince(lastConfirmationDate)
            if elapsed < 5 {
                let waitSeconds = Int(ceil(5 - elapsed))
                lockLabel.stringValue = "请再等 \(waitSeconds) 秒"
                return
            }
        }

        confirmationCount += 1
        lastConfirmationDate = now
        progressLabel.stringValue = "已确认 \(confirmationCount)/3"
        secondaryProgressLabels.forEach { $0.stringValue = "已确认 \(confirmationCount)/3" }

        if confirmationCount >= 3 {
            progressLabel.stringValue = "已确认 3/3"
            secondaryProgressLabels.forEach { $0.stringValue = "已确认 3/3" }
            lockLabel.stringValue = "完成"
            forceCloseFromConfirmation()
            return
        }

        confirmButton.isEnabled = false
        lockLabel.stringValue = "请等待 5 秒后继续确认"
        clickCooldownTimer?.invalidate()
        let timer = Timer(timeInterval: 5, repeats: false) { [weak self] _ in
            self?.confirmButton.isEnabled = true
            self?.lockLabel.stringValue = "请继续确认"
        }
        clickCooldownTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func cleanup() {
        unlockTimer?.invalidate()
        clickCooldownTimer?.invalidate()
        unlockTimer = nil
        clickCooldownTimer = nil
        player?.pause()
        secondaryPlayers.forEach { $0.pause() }
        player = nil
        looper = nil
        secondaryPlayers.removeAll()
        secondaryLoopers.removeAll()
        secondaryProgressLabels.removeAll()
        secondaryWindows.forEach { $0.orderOut(nil) }
        secondaryWindows.removeAll()
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = ReminderSettings()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let shouldResumeOnLaunch: Bool
    private let shouldTestOnLaunch: Bool
    private var schedulerTimer: Timer?
    private var activeReminder: ReminderWindowController?
    private var lastFiredSlotKey: String?

    init(shouldResumeOnLaunch: Bool, shouldTestOnLaunch: Bool) {
        self.shouldResumeOnLaunch = shouldResumeOnLaunch
        self.shouldTestOnLaunch = shouldTestOnLaunch
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if shouldResumeOnLaunch {
            settings.resumeToday()
        }
        configureStatusMenu()
        startScheduler()
        if shouldTestOnLaunch {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.showReminder()
            }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        schedulerTimer?.invalidate()
        activeReminder = nil
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

        let stateItem = NSMenuItem(title: currentStatusText(), action: nil, keyEquivalent: "")
        stateItem.isEnabled = false
        menu.addItem(stateItem)

        let nextItem = NSMenuItem(title: nextReminderText(), action: nil, keyEquivalent: "")
        nextItem.isEnabled = false
        menu.addItem(nextItem)
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "开启提醒", action: #selector(enableReminders), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "今日暂停", action: #selector(pauseToday), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "重新开启今日提醒", action: #selector(resumeToday), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "手动测试提醒窗口", action: #selector(testReminder), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出 Drinking Project", action: #selector(quitApp), keyEquivalent: "q"))
    }

    private func startScheduler() {
        schedulerTimer?.invalidate()
        schedulerTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            self?.checkSchedule()
        }
        checkSchedule()
    }

    private func checkSchedule() {
        guard settings.remindersEnabled, !settings.isPausedToday, activeReminder == nil else { return }

        let now = Date()
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: now)
        guard let hour = components.hour, let minute = components.minute else { return }
        guard hour >= 8, hour <= 22, (minute == 0 || minute == 30) else { return }
        guard hour < 22 || minute == 0 else { return }

        let slotKey = slotKey(for: now)
        guard slotKey != lastFiredSlotKey else { return }
        lastFiredSlotKey = slotKey
        showReminder()
    }

    private func showReminder() {
        BackgroundMediaControl.pauseLikelyMediaSources()
        SystemAudio.setOutputVolumeToReminderLevel()
        let reminder = ReminderWindowController(videoURL: VideoScanner.randomPlayableVideoURL())
        activeReminder = reminder
        reminder.onClosed = { [weak self] in
            self?.activeReminder = nil
        }
        reminder.present()
    }

    private func slotKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    private func currentStatusText() -> String {
        if !settings.remindersEnabled {
            return "状态：提醒已关闭"
        }
        if settings.isPausedToday {
            return "状态：今日已暂停"
        }
        return "状态：提醒运行中"
    }

    private func nextReminderText() -> String {
        if !settings.remindersEnabled || settings.isPausedToday {
            return "下次提醒：暂无"
        }

        let calendar = Calendar.current
        let now = Date()
        for offset in 0..<(60 * 24 * 2) {
            guard let candidate = calendar.date(byAdding: .minute, value: offset, to: now) else { continue }
            let parts = calendar.dateComponents([.hour, .minute], from: candidate)
            guard let hour = parts.hour, let minute = parts.minute else { continue }
            if hour >= 8, hour <= 22, (minute == 0 || minute == 30), (hour < 22 || minute == 0) {
                let formatter = DateFormatter()
                formatter.dateFormat = "MM-dd HH:mm"
                return "下次提醒：\(formatter.string(from: candidate))"
            }
        }
        return "下次提醒：暂无"
    }

    @objc private func enableReminders() {
        settings.remindersEnabled = true
        rebuildMenu()
    }

    @objc private func pauseToday() {
        settings.pauseToday()
        rebuildMenu()
    }

    @objc private func resumeToday() {
        settings.resumeToday()
        rebuildMenu()
    }

    @objc private func testReminder() {
        guard activeReminder == nil else { return }
        showReminder()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

private let app = NSApplication.shared
private let arguments = Set(CommandLine.arguments.dropFirst())
private let delegate = AppDelegate(
    shouldResumeOnLaunch: arguments.contains("--resume-on-launch"),
    shouldTestOnLaunch: arguments.contains("--test-on-launch")
)
app.delegate = delegate
app.run()
