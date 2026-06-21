import AppKit
import AVFoundation
import AVKit
import WebKit

final class ReminderWindowController: NSWindowController, NSWindowDelegate, WKNavigationDelegate, WKScriptMessageHandler {
    private let videoScanner: VideoScanner
    private let settingsStore: SettingsStore
    private let configuration: ReminderConfiguration
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

    var onClosed: (() -> Void)?
    var onCompleted: (() -> Void)?

    init(
        videoURL: URL?,
        videoScanner: VideoScanner,
        settingsStore: SettingsStore,
        configuration: ReminderConfiguration,
        webResourceDirectory: URL
    ) {
        self.videoScanner = videoScanner
        self.settingsStore = settingsStore
        self.configuration = configuration
        self.webResourceDirectory = webResourceDirectory
        playbackMode = configuration.playbackMode
        remainingLockSeconds = configuration.lockSeconds
        statusText = "\(configuration.lockSeconds) 秒后再确认"
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

        addDimView(to: contentView)
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
                statusText = "请点击 \(configuration.requiredConfirmations) 次，每次间隔至少 \(configuration.confirmationCooldownSeconds) 秒"
                hintText = "每次确认之间保留一点间隔，确保不是随手点掉。"
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
            forceCloseFromConfirmation()
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
