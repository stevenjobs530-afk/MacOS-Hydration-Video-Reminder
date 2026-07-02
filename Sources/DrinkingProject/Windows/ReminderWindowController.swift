import AppKit
import AVFoundation
import AVKit
import WebKit

final class ReminderWindowController: NSWindowController, NSWindowDelegate, WKNavigationDelegate, WKScriptMessageHandler {
    private let videoScanner: VideoScanner
    private let settingsStore: SettingsStore
    private let configuration: ReminderConfiguration
    private let mediaEnforcementReport: BackgroundMediaEnforcementReport
    private let webResourceDirectory: URL
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var primaryEndObserver: NSObjectProtocol?
    private var webView: WKWebView?
    private var secondaryWindows: [ReminderWindow] = []
    private var secondaryPlayers: [AVQueuePlayer] = []
    private var secondaryLoopers: [AVPlayerLooper] = []
    private var secondaryWebViews: [WKWebView] = []
    private var currentVideoURL: URL?
    private var playbackMode: VideoPlaybackMode
    private var unlockTimer: Timer?
    private var clickCooldownTimer: Timer?
    private var remainingLockSeconds: Int
    private var confirmationCount = 0
    private var lastConfirmationDate: Date?
    private var mayClose = false
    private var statusText: String
    private var hintText = "把杯子拿起来，慢慢喝完这一口。"
    private var buttonText = "等待中"
    private var isConfirmationVisible = false
    private var isConfirmationEnabled = false
    private let hasPlayableVideo: Bool
    /// Compact "Mac 弹窗" style: a small centered panel on the main screen only,
    /// no video, with a pop-in animation. The Swift lock/confirm flow is identical.
    private let isCompact: Bool
    private static let compactWindowSize = NSSize(width: 460, height: 340)

    var onClosed: (() -> Void)?
    var onCompleted: (() -> Void)?

    init(
        videoURL: URL?,
        videoScanner: VideoScanner,
        settingsStore: SettingsStore,
        configuration: ReminderConfiguration,
        mediaEnforcementReport: BackgroundMediaEnforcementReport,
        webResourceDirectory: URL
    ) {
        self.videoScanner = videoScanner
        self.settingsStore = settingsStore
        self.configuration = configuration
        self.mediaEnforcementReport = mediaEnforcementReport
        self.webResourceDirectory = webResourceDirectory
        playbackMode = configuration.playbackMode
        remainingLockSeconds = configuration.lockSeconds
        statusText = "\(configuration.lockSeconds) 秒后再确认"
        hintText = configuration.friendlyMessage
        hasPlayableVideo = videoURL != nil
        let isCompact = configuration.windowStyle == .compactPopup
        self.isCompact = isCompact

        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let contentRect: NSRect
        if isCompact {
            let size = Self.compactWindowSize
            contentRect = NSRect(
                x: screenFrame.midX - size.width / 2,
                y: screenFrame.midY - size.height / 2,
                width: size.width,
                height: size.height
            )
        } else {
            contentRect = screenFrame
        }
        let window = ReminderWindow(
            contentRect: contentRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isReleasedWhenClosed = false
        if isCompact {
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = true
        } else {
            window.backgroundColor = .black
        }
        super.init(window: window)
        window.delegate = self
        window.onCloseShortcut = { [weak self] in
            self?.closeReminder()
        }
        buildInterface(videoURL: videoURL)
        if !isCompact && settingsStore.settings.reminderScreenMode == .allScreens {
            buildSecondaryScreenWindows(videoURL: videoURL)
        }
        setCurrentVideo(videoURL, shouldPlay: false)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func present() {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        if isCompact {
            centerCompactWindow(window)
        } else {
            window.setFrame(NSScreen.main?.frame ?? window.frame, display: true)
        }
        for secondaryWindow in secondaryWindows {
            secondaryWindow.orderFrontRegardless()
        }
        window.makeKeyAndOrderFront(nil)
        if isCompact {
            animateCompactPopIn(window)
        }
        startLockCountdown()
        player?.play()
        secondaryPlayers.forEach { $0.play() }
    }

    private func centerCompactWindow(_ window: NSWindow) {
        let screenFrame = NSScreen.main?.visibleFrame ?? window.frame
        let size = Self.compactWindowSize
        // Slightly above true center, matching where macOS places alert panels.
        let origin = NSPoint(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.minY + (screenFrame.height - size.height) * 0.58
        )
        window.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    /// Mac-style pop-in: the panel springs up from ~86% scale while fading in,
    /// like a system alert appearing.
    private func animateCompactPopIn(_ window: NSWindow) {
        guard let layer = window.contentView?.layer else { return }
        let bounds = layer.bounds
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.position = CGPoint(x: bounds.midX, y: bounds.midY)

        let scale = CASpringAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.86
        scale.toValue = 1.0
        scale.mass = 1
        scale.stiffness = 320
        scale.damping = 20
        scale.initialVelocity = 6
        scale.duration = scale.settlingDuration
        layer.add(scale, forKey: "compactPopIn")

        window.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }
    }

    /// Cleanly close the reminder (timers, players, secondary screens, web handlers) without
    /// quitting the app. Used by both the completion path and the Command+W shortcut.
    /// Does not record a drinking completion; callers record that separately when relevant.
    func closeReminder() {
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

        if isCompact {
            contentView.layer?.backgroundColor = NSColor.clear.cgColor
            let card = addCompactCard(to: contentView)
            webView = addReminderWebView(to: card, role: "primary")
            return
        }

        contentView.layer?.backgroundColor = NSColor.black.cgColor

        if let videoURL {
            let queuePlayer = AVQueuePlayer()
            configureVideoAudio(for: queuePlayer, emitsAudio: true)
            player = queuePlayer
            addCenteredPlayerView(player: queuePlayer, videoURL: videoURL, to: contentView)
        }

        addDimView(to: contentView)
        webView = addReminderWebView(to: contentView, role: "primary")
    }

    /// Rounded dark vibrancy panel that hosts the compact reminder UI.
    private func addCompactCard(to contentView: NSView) -> NSView {
        let card = NSVisualEffectView()
        card.material = .hudWindow
        card.blendingMode = .behindWindow
        card.state = .active
        card.wantsLayer = true
        card.layer?.cornerRadius = 18
        card.layer?.cornerCurve = .continuous
        card.layer?.masksToBounds = true
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        card.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(card)
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            card.topAnchor.constraint(equalTo: contentView.topAnchor),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
        return card
    }

    private func buildSecondaryScreenWindows(videoURL: URL?) {
        // The reminder always covers every connected display simultaneously, whether the
        // built-in laptop screen or an external monitor. There is no "main screen only" mode.
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
            secondaryWindow.onCloseShortcut = { [weak self] in
                self?.closeReminder()
            }

            let contentView = NSView(frame: screen.frame)
            contentView.wantsLayer = true
            contentView.layer?.backgroundColor = NSColor.black.cgColor
            secondaryWindow.contentView = contentView

            if let videoURL {
                let queuePlayer = AVQueuePlayer()
                configureVideoAudio(for: queuePlayer, emitsAudio: false)
                addCenteredPlayerView(player: queuePlayer, videoURL: videoURL, to: contentView)
                secondaryPlayers.append(queuePlayer)
            }

            addDimView(to: contentView)
            secondaryWebViews.append(addReminderWebView(to: contentView, role: "secondary"))
            secondaryWindows.append(secondaryWindow)
        }
    }

    private func addDimView(to contentView: NSView) {
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

        let indexURL = webResourceDirectory.appendingPathComponent("index.html")
        reminderView.loadFileURL(indexURL, allowingReadAccessTo: webResourceDirectory)
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

    private func configureVideoAudio(for queuePlayer: AVQueuePlayer, emitsAudio: Bool) {
        let volume = emitsAudio ? settingsStore.settings.reminderAudioVolume : 0
        queuePlayer.isMuted = volume <= 0
        queuePlayer.volume = volume
    }

    private func setPlaybackMode(_ mode: VideoPlaybackMode) {
        playbackMode = mode
        settingsStore.settings.playbackMode = mode
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
        guard let nextVideoURL = videoScanner.nextPlayableVideoURL() else { return }
        setCurrentVideo(nextVideoURL, shouldPlay: true)
    }

    private func startLockCountdown() {
        remainingLockSeconds = configuration.lockSeconds
        confirmationCount = 0
        lastConfirmationDate = nil
        statusText = "\(configuration.lockSeconds) 秒后再确认"
        hintText = configuration.friendlyMessage
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
                statusText = "请点击 \(configuration.requiredConfirmations) 次，每次间隔至少 \(configuration.confirmationCooldownSeconds) 秒"
                hintText = configuration.isPlaygroundMode
                    ? "测试模式已缩短确认流程，点一次就能完成。"
                    : "每次确认之间保留一点间隔，确保不是随手点掉。"
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
            let cooldown = TimeInterval(configuration.confirmationCooldownSeconds)
            if elapsed < cooldown {
                let waitSeconds = Int(ceil(cooldown - elapsed))
                statusText = "请再等 \(waitSeconds) 秒"
                hintText = "留一点间隔，让喝水不是一次机械点击。"
                updateWebReminderViews()
                return
            }
        }

        confirmationCount += 1
        lastConfirmationDate = now
        updateWebReminderViews()

        if confirmationCount >= configuration.requiredConfirmations {
            statusText = "完成"
            hintText = "很好，回去继续。"
            buttonText = "完成"
            isConfirmationEnabled = false
            updateWebReminderViews()
            onCompleted?()
            closeReminder()
            return
        }

        isConfirmationEnabled = false
        statusText = "请等待 \(configuration.confirmationCooldownSeconds) 秒后继续确认"
        hintText = "把杯子放下前，再喝一口。"
        buttonText = "冷却中"
        updateWebReminderViews()
        clickCooldownTimer?.invalidate()
        let timer = Timer(timeInterval: TimeInterval(configuration.confirmationCooldownSeconds), repeats: false) { [weak self] _ in
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
            "requiredConfirmations": configuration.requiredConfirmations,
            "buttonVisible": isConfirmationVisible,
            "buttonEnabled": isConfirmationEnabled,
            "statusText": statusText,
            "hintText": hintText,
            "buttonText": buttonText,
            "playbackMode": playbackMode.rawValue,
            "hasPlayableVideo": hasPlayableVideo,
            "isCompact": isCompact,
            "isPlaygroundMode": configuration.isPlaygroundMode,
            "friendlyMessage": configuration.friendlyMessage,
            "testModeText": "测试模式：等待时间已缩短",
            "mediaWarningText": mediaEnforcementReport.reminderWarningText ?? "",
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
