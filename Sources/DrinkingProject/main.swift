import AppKit
import AVFoundation
import AVKit
import IOKit
import WebKit

private let projectDirectory = URL(
    fileURLWithPath: FileManager.default.currentDirectoryPath,
    isDirectory: true
)
private let videoDirectory = projectDirectory.appendingPathComponent("视频", isDirectory: true)
private let videoMaterialDirectory = videoDirectory.appendingPathComponent("视频素材", isDirectory: true)
private let reminderWebDirectory = projectDirectory
    .appendingPathComponent("Test ", isDirectory: true)
    .appendingPathComponent("ReminderWeb", isDirectory: true)

private enum DefaultsKey {
    static let remindersEnabled = "remindersEnabled"
    static let pausedDate = "pausedDate"
    static let videoPlaybackMode = "videoPlaybackMode"
}

private enum VideoPlaybackMode: String {
    case advanceOnEnd
    case loopSelected

    static func load() -> VideoPlaybackMode {
        let rawValue = UserDefaults.standard.string(forKey: DefaultsKey.videoPlaybackMode)
        return rawValue.flatMap(VideoPlaybackMode.init(rawValue:)) ?? .advanceOnEnd
    }

    func save() {
        UserDefaults.standard.set(rawValue, forKey: DefaultsKey.videoPlaybackMode)
    }
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
    private struct ScanResult {
        let candidates: [URL]
        let playableVideos: [URL]
        let notPlayableVideos: [URL]
    }

    private static var shuffledQueue: [URL] = []
    private static var lastPlayableSignature: [String] = []

    static func nextPlayableVideoURL() -> URL? {
        let result = scanVideos()
        let playableSignature = result.playableVideos.map(\.path)

        if playableSignature != lastPlayableSignature || shuffledQueue.isEmpty {
            shuffledQueue = result.playableVideos.shuffled()
            lastPlayableSignature = playableSignature
        }

        let selectedVideo = shuffledQueue.popLast()
        logScanResult(result, selectedVideo: selectedVideo)
        return selectedVideo
    }

    private static func scanVideos() -> ScanResult {
        let allowedExtensions = Set(["mp4", "mov", "m4v"])
        let searchDirectories = [videoMaterialDirectory, videoDirectory]
        var seenPaths = Set<String>()
        var candidates: [URL] = []

        for directory in searchDirectories {
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for url in files {
                guard
                    !url.lastPathComponent.hasPrefix("._"),
                    allowedExtensions.contains(url.pathExtension.lowercased()),
                    ((try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false),
                    !seenPaths.contains(url.path)
                else {
                    continue
                }
                candidates.append(url)
                seenPaths.insert(url.path)
            }
        }

        candidates.sort {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }

        let playableVideos = candidates.filter { url in
            AVURLAsset(url: url).isPlayable
        }
        let playablePaths = Set(playableVideos.map(\.path))
        let notPlayableVideos = candidates.filter { !playablePaths.contains($0.path) }

        return ScanResult(
            candidates: candidates,
            playableVideos: playableVideos,
            notPlayableVideos: notPlayableVideos
        )
    }

    private static func logScanResult(_ result: ScanResult, selectedVideo: URL?) {
        let notPlayableNames = result.notPlayableVideos
            .map(\.lastPathComponent)
            .joined(separator: ",")
        let selectedName = selectedVideo?.lastPathComponent ?? "none"
        print(
            "[DrinkingProject] video_scan candidate_count=\(result.candidates.count) " +
                "playable_count=\(result.playableVideos.count) " +
                "selected_video=\(selectedName) " +
                "not_playable_files=\(notPlayableNames.isEmpty ? "none" : notPlayableNames)"
        )
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

private final class ReminderWindowController: NSWindowController, NSWindowDelegate, WKNavigationDelegate, WKScriptMessageHandler {
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var primaryEndObserver: NSObjectProtocol?
    private var webView: WKWebView?
    private var secondaryWindows: [ReminderWindow] = []
    private var secondaryPlayers: [AVQueuePlayer] = []
    private var secondaryLoopers: [AVPlayerLooper] = []
    private var secondaryWebViews: [WKWebView] = []
    private var currentVideoURL: URL?
    private var playbackMode = VideoPlaybackMode.load()
    private var unlockTimer: Timer?
    private var clickCooldownTimer: Timer?
    private var remainingLockSeconds = 30
    private var confirmationCount = 0
    private var lastConfirmationDate: Date?
    private var mayClose = false
    private var statusText = "30 秒后再确认"
    private var hintText = "把杯子拿起来，慢慢喝完这一口。"
    private var buttonText = "等待中"
    private var isConfirmationVisible = false
    private var isConfirmationEnabled = false
    private let hasPlayableVideo: Bool

    var onClosed: (() -> Void)?

    init(videoURL: URL?) {
        hasPlayableVideo = videoURL != nil
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
        setCurrentVideo(videoURL, shouldPlay: false)
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

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let role = webView === self.webView ? "primary" : "secondary"
        sendState(to: webView, role: role)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "drinkingProject" else { return }
        guard
            let body = message.body as? [String: Any],
            let type = body["type"] as? String
        else {
            return
        }

        switch type {
        case "confirmWater":
            confirmWater()
        case "setPlaybackMode":
            guard
                let rawMode = body["mode"] as? String,
                let mode = VideoPlaybackMode(rawValue: rawMode)
            else {
                return
            }
            setPlaybackMode(mode)
        default:
            break
        }
    }

    private func buildInterface(videoURL: URL?) {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.black.cgColor

        if let videoURL {
            let queuePlayer = AVQueuePlayer()
            queuePlayer.isMuted = false
            queuePlayer.volume = 1.0
            player = queuePlayer

            addCenteredPlayerView(player: queuePlayer, videoURL: videoURL, to: contentView)
        }

        let dimView = NSView()
        dimView.wantsLayer = true
        dimView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.08).cgColor
        dimView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(dimView)
        NSLayoutConstraint.activate([
            dimView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            dimView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            dimView.topAnchor.constraint(equalTo: contentView.topAnchor),
            dimView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        webView = addReminderWebView(to: contentView, role: "primary")
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
                let queuePlayer = AVQueuePlayer()
                queuePlayer.isMuted = true
                queuePlayer.volume = 0

                addCenteredPlayerView(player: queuePlayer, videoURL: videoURL, to: contentView)

                secondaryPlayers.append(queuePlayer)
            }

            let dimView = NSView()
            dimView.wantsLayer = true
            dimView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.08).cgColor
            dimView.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(dimView)
            NSLayoutConstraint.activate([
                dimView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                dimView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                dimView.topAnchor.constraint(equalTo: contentView.topAnchor),
                dimView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
            ])

            secondaryWebViews.append(addReminderWebView(to: contentView, role: "secondary"))

            secondaryWindows.append(secondaryWindow)
        }
    }

    private func addReminderWebView(to contentView: NSView, role: String) -> WKWebView {
        let userContentController = WKUserContentController()
        if role == "primary" {
            userContentController.add(self, name: "drinkingProject")
        }

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = userContentController

        let reminderView = WKWebView(frame: .zero, configuration: configuration)
        reminderView.navigationDelegate = self
        reminderView.translatesAutoresizingMaskIntoConstraints = false
        reminderView.wantsLayer = true
        reminderView.layer?.backgroundColor = NSColor.clear.cgColor
        reminderView.setValue(false, forKey: "drawsBackground")
        contentView.addSubview(reminderView)

        NSLayoutConstraint.activate([
            reminderView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            reminderView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            reminderView.topAnchor.constraint(equalTo: contentView.topAnchor),
            reminderView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        let indexURL = reminderWebDirectory.appendingPathComponent("index.html")
        reminderView.loadFileURL(indexURL, allowingReadAccessTo: reminderWebDirectory)
        return reminderView
    }

    private func addCenteredPlayerView(player: AVQueuePlayer, videoURL: URL, to contentView: NSView) {
        let playerView = AVPlayerView()
        playerView.player = player
        playerView.controlsStyle = .none
        playerView.videoGravity = .resizeAspectFill
        playerView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(playerView)

        NSLayoutConstraint.activate([
            playerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            playerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            playerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    private func setPlaybackMode(_ mode: VideoPlaybackMode) {
        playbackMode = mode
        playbackMode.save()
        setCurrentVideo(currentVideoURL, shouldPlay: player?.timeControlStatus == .playing)
        updateWebReminderViews()
    }

    private func setCurrentVideo(_ videoURL: URL?, shouldPlay: Bool) {
        removePrimaryEndObserver()
        looper = nil
        secondaryLoopers.removeAll()
        currentVideoURL = videoURL

        guard let videoURL else {
            player?.replaceCurrentItem(with: nil)
            secondaryPlayers.forEach { $0.replaceCurrentItem(with: nil) }
            return
        }

        if let player {
            let item = AVPlayerItem(url: videoURL)
            player.actionAtItemEnd = playbackMode == .loopSelected ? .none : .pause
            player.replaceCurrentItem(with: item)

            switch playbackMode {
            case .advanceOnEnd:
                observePrimaryItemEnd(item)
            case .loopSelected:
                looper = AVPlayerLooper(player: player, templateItem: item)
            }
        }

        for secondaryPlayer in secondaryPlayers {
            let item = AVPlayerItem(url: videoURL)
            secondaryPlayer.actionAtItemEnd = playbackMode == .loopSelected ? .none : .pause
            secondaryPlayer.replaceCurrentItem(with: item)
            if playbackMode == .loopSelected {
                secondaryLoopers.append(AVPlayerLooper(player: secondaryPlayer, templateItem: item))
            }
        }

        if shouldPlay {
            player?.play()
            secondaryPlayers.forEach { $0.play() }
        }
    }

    private func observePrimaryItemEnd(_ item: AVPlayerItem) {
        primaryEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.advanceToNextVideo()
        }
    }

    private func removePrimaryEndObserver() {
        if let primaryEndObserver {
            NotificationCenter.default.removeObserver(primaryEndObserver)
            self.primaryEndObserver = nil
        }
    }

    private func advanceToNextVideo() {
        guard playbackMode == .advanceOnEnd else { return }
        guard let nextVideoURL = VideoScanner.nextPlayableVideoURL() else { return }
        setCurrentVideo(nextVideoURL, shouldPlay: true)
    }

    private func startLockCountdown() {
        remainingLockSeconds = 30
        confirmationCount = 0
        lastConfirmationDate = nil
        statusText = "30 秒后再确认"
        hintText = "把杯子拿起来，慢慢喝完这一口。"
        buttonText = "等待中"
        isConfirmationVisible = false
        isConfirmationEnabled = false
        updateWebReminderViews()

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] timer in
            guard let self else { return }
            remainingLockSeconds -= 1
            if remainingLockSeconds > 0 {
                statusText = "\(remainingLockSeconds) 秒后再确认"
            } else {
                timer.invalidate()
                unlockTimer = nil
                statusText = "请点击 3 次，每次间隔至少 5 秒"
                hintText = "每次确认之间保留 5 秒，确保不是随手点掉。"
                buttonText = "已饮水"
                isConfirmationVisible = true
                isConfirmationEnabled = true
            }
            updateWebReminderViews()
        }
        unlockTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func confirmWater() {
        guard isConfirmationVisible, isConfirmationEnabled else { return }

        let now = Date()
        if let lastConfirmationDate {
            let elapsed = now.timeIntervalSince(lastConfirmationDate)
            if elapsed < 5 {
                let waitSeconds = Int(ceil(5 - elapsed))
                statusText = "请再等 \(waitSeconds) 秒"
                hintText = "留一点间隔，让喝水不是一次机械点击。"
                updateWebReminderViews()
                return
            }
        }

        confirmationCount += 1
        lastConfirmationDate = now
        updateWebReminderViews()

        if confirmationCount >= 3 {
            statusText = "完成"
            hintText = "很好，回去继续。"
            buttonText = "完成"
            isConfirmationEnabled = false
            updateWebReminderViews()
            forceCloseFromConfirmation()
            return
        }

        isConfirmationEnabled = false
        statusText = "请等待 5 秒后继续确认"
        hintText = "把杯子放下前，再喝一口。"
        buttonText = "冷却中"
        updateWebReminderViews()
        clickCooldownTimer?.invalidate()
        let timer = Timer(timeInterval: 5, repeats: false) { [weak self] _ in
            self?.isConfirmationEnabled = true
            self?.statusText = "请继续确认"
            self?.hintText = "还差几次，慢一点也没关系。"
            self?.buttonText = "已饮水"
            self?.updateWebReminderViews()
        }
        clickCooldownTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func updateWebReminderViews() {
        sendState(to: webView, role: "primary")
        secondaryWebViews.forEach { sendState(to: $0, role: "secondary") }
    }

    private func sendState(to reminderView: WKWebView?, role: String) {
        guard let reminderView else { return }
        let payload: [String: Any] = [
            "role": role,
            "remainingSeconds": remainingLockSeconds,
            "confirmationCount": confirmationCount,
            "requiredConfirmations": 3,
            "buttonVisible": isConfirmationVisible,
            "buttonEnabled": isConfirmationEnabled,
            "statusText": statusText,
            "hintText": hintText,
            "buttonText": buttonText,
            "playbackMode": playbackMode.rawValue,
            "hasPlayableVideo": hasPlayableVideo,
            "videoMessage": "未找到可播放视频，请检查 视频/视频素材/"
        ]
        guard
            let data = try? JSONSerialization.data(withJSONObject: payload),
            let json = String(data: data, encoding: .utf8)
        else {
            return
        }
        reminderView.evaluateJavaScript("window.drinkingProjectState && window.drinkingProjectState(\(json));")
    }

    private func cleanup() {
        unlockTimer?.invalidate()
        clickCooldownTimer?.invalidate()
        unlockTimer = nil
        clickCooldownTimer = nil
        removePrimaryEndObserver()
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "drinkingProject")
        webView = nil
        player?.pause()
        secondaryPlayers.forEach { $0.pause() }
        player = nil
        looper = nil
        secondaryPlayers.removeAll()
        secondaryLoopers.removeAll()
        secondaryWebViews.removeAll()
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
        let reminder = ReminderWindowController(videoURL: VideoScanner.nextPlayableVideoURL())
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
