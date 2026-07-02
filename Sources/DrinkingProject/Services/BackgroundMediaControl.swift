import ApplicationServices
import AppKit

struct BrowserMediaEnforcementDetail: Equatable {
    var browserName: String
    var tabsChecked = 0
    var tabsSucceeded = 0
    var tabsFailed = 0
    var mediaFound = 0
    var mediaPaused = 0
    var mediaMuted = 0
    var iframeBlocked = 0
    var errors: [String] = []
    var notes: [String] = []

    var hasFailure: Bool {
        tabsFailed > 0 || (tabsChecked == 0 && tabsSucceeded == 0) || !errors.isEmpty
    }

    var readinessText: String {
        if tabsChecked == 0 {
            return "\(browserName)：需要打开至少一个可控标签页"
        }
        if hasFailure {
            return "\(browserName)：需要系统自动化授权或浏览器 JavaScript 控制权限"
        }
        return "\(browserName)：已就绪"
    }

    var summaryText: String {
        var parts = [
            "\(browserName)：标签页 \(tabsSucceeded)/\(tabsChecked)",
            "媒体 \(mediaFound)",
            "暂停 \(mediaPaused)",
            "静音 \(mediaMuted)"
        ]
        if iframeBlocked > 0 {
            parts.append("跨域 iframe \(iframeBlocked)")
        }
        if !errors.isEmpty {
            parts.append("错误 \(errors.prefix(2).joined(separator: "；"))")
        }
        if !notes.isEmpty {
            parts.append(notes.prefix(2).joined(separator: "；"))
        }
        return parts.joined(separator: "，")
    }
}

/// Structured result of a forced background-media enforcement pass.
/// `pausedApps` means direct pause/mute commands were accepted; browser details
/// carry the stronger per-tab evidence for Chrome/Safari.
struct BackgroundMediaEnforcementReport: Equatable {
    var attemptedApps: [String] = []
    var pausedApps: [String] = []
    var skippedApps: [String] = []
    var failedApps: [String] = []
    var notes: [String] = []
    var browserDetails: [BrowserMediaEnforcementDetail] = []

    private static func joined(_ values: [String]) -> String {
        values.isEmpty ? "none" : values.joined(separator: ",")
    }

    /// One-line structured log string.
    var logLine: String {
        let browserSummary = browserDetails.isEmpty
            ? "none"
            : browserDetails.map { detail in
                "\(detail.browserName):tabs=\(detail.tabsSucceeded)/\(detail.tabsChecked),media=\(detail.mediaFound),paused=\(detail.mediaPaused),muted=\(detail.mediaMuted),iframe=\(detail.iframeBlocked),errors=\(detail.errors.count)"
            }.joined(separator: " | ")
        return "[DrinkingProject] media_enforce attempted=\(Self.joined(attemptedApps)) "
            + "paused=\(Self.joined(pausedApps)) "
            + "skipped=\(Self.joined(skippedApps)) "
            + "failed=\(Self.joined(failedApps)) "
            + "browsers=\(browserSummary) "
            + "notes=\(notes.isEmpty ? "none" : notes.joined(separator: " | "))"
    }

    private static func display(_ values: [String]) -> String {
        values.isEmpty ? "无" : values.joined(separator: "、")
    }

    /// Human-readable multi-line summary for the settings test button.
    var summaryText: String {
        var lines: [String] = []
        lines.append("后台媒体暂停：尽力执行")
        lines.append("已检查：\(Self.display(attemptedApps))")
        lines.append("已暂停或静音：\(Self.display(pausedApps))")
        lines.append("跳过：\(Self.display(skippedApps))")
        lines.append("失败：\(Self.display(failedApps))")
        if !browserDetails.isEmpty {
            lines.append("浏览器详情：")
            lines.append(contentsOf: browserDetails.map(\.summaryText))
        }
        if !notes.isEmpty {
            lines.append("说明：\(notes.joined(separator: "；"))")
        }
        return lines.joined(separator: "\n")
    }

    var hasBlockingBrowserFailure: Bool {
        false
    }

    var reminderWarningText: String? {
        nil
    }

    static var noBrowserIssues: BackgroundMediaEnforcementReport {
        BackgroundMediaEnforcementReport()
    }
}

enum BackgroundMediaControl {
    private static let weReadBundleIdentifier = "com.tencent.weread"
    private static let weReadPlayButtonIdentifier = "ViewID_PlayerToolBarPlay"

    /// NetEase Cloud Music has no public AppleScript pause command, so we drive it via
    /// Accessibility instead. Known bundle ids across versions; we also fall back to name match.
    private static let netEaseBundleIdentifiers = ["com.netease.163music", "com.netease.NeteaseMusic"]
    private static let netEaseAppNames = ["网易云音乐", "NeteaseMusic", "NetEaseMusic", "NetEase Cloud Music"]
    /// Accessibility titles/descriptions that mean "pressing this pauses currently-playing media".
    /// Matching only these guarantees we never resume something that is already paused.
    private static let pauseControlLabels = ["暂停", "Pause"]

    private enum BrowserScriptKind {
        case safari
        case chromium
    }

    private enum AppleScriptStringResult {
        case success(String)
        case failure(String)
    }

    /// Browsers we can drive with Apple Events. All browser control is best-effort:
    /// failures are logged for diagnostics but never block or mute the reminder.
    private static let browserCommands: [(name: String, kind: BrowserScriptKind, requiresStrictReadiness: Bool)] = [
        ("Safari", .safari, true),
        ("Google Chrome", .chromium, true),
        ("Microsoft Edge", .chromium, false),
        ("Brave Browser", .chromium, false),
        ("Arc", .chromium, false),
        ("Vivaldi", .chromium, false),
        ("Opera", .chromium, false)
    ]

    /// Players we pause with an explicit `pause` command (never a toggle). Order is the attempt order.
    /// Multiple NetEase aliases map to the same app under different localized names.
    private static let playerScripts: [(name: String, script: String)] = [
        ("Music", #"tell application "Music" to pause"#),
        ("TV", #"tell application "TV" to pause"#),
        ("Spotify", #"tell application "Spotify" to pause"#),
        ("Podcasts", #"tell application "Podcasts" to pause"#),
        ("QuickTime Player", #"tell application "QuickTime Player" to pause every document"#),
        ("IINA", #"tell application "IINA" to pause"#),
        ("VLC", #"tell application "VLC" to pause"#),
        ("Elmedia Player", #"tell application "Elmedia Player" to pause"#)
        // 网易云音乐没有公开可用的 pause AppleScript 命令，改走辅助功能路径（见 pauseNetEaseMusic）。
    ]

    /// User-facing lists for the settings page (curated, de-duplicated).
    static let supportedBrowserDisplayNames = ["Safari", "Google Chrome", "Microsoft Edge", "Brave Browser", "Arc", "Vivaldi", "Opera"]
    static let supportedPlayerDisplayNames = ["Music", "TV", "Spotify", "Podcasts", "QuickTime Player", "IINA", "VLC", "Elmedia Player", "网易云音乐", "微信读书"]

    @discardableResult
    static func enforceBackgroundMediaPause(includeInactiveDiagnostics: Bool = false) -> BackgroundMediaEnforcementReport {
        var report = BackgroundMediaEnforcementReport()
        enforceBrowserMedia(into: &report)
        pauseKnownPlayerApps(into: &report)
        pauseNetEaseMusic(into: &report, includeInactiveDiagnostics: includeInactiveDiagnostics)
        pauseWeReadMedia(into: &report)
        report.notes.append("不会杀进程、不会修改系统总音量、不会模拟全局媒体键")
        print(report.logLine)
        return report
    }

    /// Whether this app currently has Accessibility (辅助功能) permission.
    /// Used only for a read-only status display; does not prompt.
    static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    /// Open System Settings at the Accessibility privacy pane so the user can grant permission.
    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    static func browserReadinessSummary() -> String {
        var lines: [String] = []
        for (appName, _, strict) in browserCommands where strict {
            if isRunning(appName) {
                lines.append("\(appName)：运行中，可尝试尽力暂停标签页媒体")
            } else {
                lines.append("\(appName)：未运行，提醒会正常播放")
            }
        }
        lines.append(hasAccessibilityPermission ? "辅助功能权限：已授权" : "辅助功能权限：未授权")
        return lines.joined(separator: "\n")
    }

    private static func enforceBrowserMedia(into report: inout BackgroundMediaEnforcementReport) {
        for (appName, kind, _) in browserCommands {
            guard isRunning(appName) else { continue }
            report.attemptedApps.append(appName)
            let detail = enforceBrowser(appName: appName, kind: kind)
            report.browserDetails.append(detail)
            if detail.hasFailure {
                report.skippedApps.append(appName)
                report.notes.append(contentsOf: browserFixNotes(for: appName, detail: detail))
            } else {
                report.pausedApps.append(appName)
            }
        }
    }

    private static func enforceBrowser(appName: String, kind: BrowserScriptKind) -> BrowserMediaEnforcementDetail {
        let source: String
        switch kind {
        case .safari:
            source = safariBrowserScript(appName: appName)
        case .chromium:
            source = chromiumBrowserScript(appName: appName)
        }

        let result = runAppleScriptReturningString(source)
        var detail = BrowserMediaEnforcementDetail(browserName: appName)
        switch result {
        case .success(let output):
            parseBrowserOutput(output, into: &detail)
            if detail.tabsChecked == 0 {
                detail.errors.append("没有找到可控标签页")
            }
        case .failure(let message):
            detail.tabsFailed += 1
            detail.errors.append(message)
        }
        return detail
    }

    private static func browserFixNotes(for appName: String, detail: BrowserMediaEnforcementDetail) -> [String] {
        var notes: [String] = []
        if detail.tabsChecked == 0 {
            notes.append("\(appName) 没有可控标签页，已跳过；提醒播放不受影响")
            return notes
        }
        if appName == "Safari" {
            notes.append("Safari 标签页暂停未完成；可检查 Allow JavaScript from Apple Events 或自动化授权，提醒播放不受影响")
        } else if appName == "Google Chrome" {
            notes.append("Chrome 标签页暂停未完成；可检查自动化授权或页面脚本权限，提醒播放不受影响")
        } else {
            notes.append("\(appName) 标签页暂停未完成，提醒播放不受影响")
        }
        if detail.iframeBlocked > 0 {
            notes.append("\(appName) 有 \(detail.iframeBlocked) 个跨域 iframe 无法进入，已对可控媒体执行暂停/静音")
        }
        return notes
    }

    private static func safariBrowserScript(appName: String) -> String {
        let script = appleScriptLiteral(browserJavaScript())
        return """
        tell application "\(appName)"
            set dpOutput to ""
            repeat with browserWindow in windows
                repeat with browserTab in tabs of browserWindow
                    try
                        set dpResult to do JavaScript \(script) in browserTab
                        set dpOutput to dpOutput & "ok|" & dpResult & "__DP_TAB__"
                    on error errMsg number errNum
                        set dpOutput to dpOutput & "error|" & errNum & "|" & errMsg & "__DP_TAB__"
                    end try
                end repeat
            end repeat
            return dpOutput
        end tell
        """
    }

    private static func chromiumBrowserScript(appName: String) -> String {
        let script = appleScriptLiteral(browserJavaScript())
        return """
        tell application "\(appName)"
            set dpOutput to ""
            repeat with browserWindow in windows
                repeat with browserTab in tabs of browserWindow
                    try
                        set dpResult to execute browserTab javascript \(script)
                        try
                            set muted of browserTab to true
                        end try
                        set dpOutput to dpOutput & "ok|" & dpResult & "__DP_TAB__"
                    on error errMsg number errNum
                        set dpOutput to dpOutput & "error|" & errNum & "|" & errMsg & "__DP_TAB__"
                    end try
                end repeat
            end repeat
            return dpOutput
        end tell
        """
    }

    private static func browserJavaScript() -> String {
        """
        (function(){
          var found=0, paused=0, already=0, muted=0, blocked=0, errors=0;
          var seen=[];
          function remember(media){ if(seen.indexOf(media)===-1){ seen.push(media); } }
          function scan(root){
            if(!root){ return; }
            try {
              if(root.querySelectorAll){
                root.querySelectorAll('video,audio').forEach(remember);
                root.querySelectorAll('*').forEach(function(node){
                  if(node.shadowRoot){ scan(node.shadowRoot); }
                });
                root.querySelectorAll('iframe').forEach(function(frame){
                  try {
                    if(frame.contentDocument){ scan(frame.contentDocument); }
                    else { blocked++; }
                  } catch(e) { blocked++; }
                });
              }
            } catch(e) { errors++; }
          }
          scan(document);
          found = seen.length;
          for(var pass=0; pass<3; pass++){
            seen.forEach(function(media){
              try {
                if(media.paused){ already++; }
                media.pause();
                media.muted = true;
                media.volume = 0;
                if(media.paused){ paused++; }
                if(media.muted || media.volume === 0){ muted++; }
              } catch(e) { errors++; }
            });
          }
          return 'found=' + found + ';paused=' + paused + ';already=' + already + ';muted=' + muted + ';blocked=' + blocked + ';errors=' + errors;
        }());
        """
    }

    private static func parseBrowserOutput(_ output: String, into detail: inout BrowserMediaEnforcementDetail) {
        for rawEntry in output.components(separatedBy: "__DP_TAB__") {
            let entry = rawEntry.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !entry.isEmpty else { continue }
            detail.tabsChecked += 1
            if entry.hasPrefix("ok|") {
                detail.tabsSucceeded += 1
                parseBrowserStats(String(entry.dropFirst(3)), into: &detail)
            } else if entry.hasPrefix("error|") {
                detail.tabsFailed += 1
                detail.errors.append(String(entry.dropFirst(6)))
            } else {
                detail.tabsFailed += 1
                detail.errors.append(entry)
            }
        }
    }

    private static func parseBrowserStats(_ stats: String, into detail: inout BrowserMediaEnforcementDetail) {
        var values: [String: Int] = [:]
        for part in stats.split(separator: ";") {
            let pair = part.split(separator: "=", maxSplits: 1)
            guard pair.count == 2 else { continue }
            values[String(pair[0])] = Int(pair[1]) ?? 0
        }
        detail.mediaFound += values["found"] ?? 0
        detail.mediaPaused += values["paused"] ?? 0
        detail.mediaMuted += values["muted"] ?? 0
        detail.iframeBlocked += values["blocked"] ?? 0
        let scriptErrors = values["errors"] ?? 0
        if scriptErrors > 0 {
            detail.errors.append("页面脚本错误 \(scriptErrors)")
        }
        if (values["found"] ?? 0) == 0 {
            detail.notes.append("未发现 video/audio")
        }
    }

    private static func appleScriptLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
        return "\"\(escaped)\""
    }

    private static func pauseKnownPlayerApps(into report: inout BackgroundMediaEnforcementReport) {
        // Use explicit pause commands only. Play/pause media-key toggles can restart paused media.
        for (appName, script) in playerScripts where isRunning(appName) {
            report.attemptedApps.append(appName)
            if runAppleScript(script) {
                report.pausedApps.append(appName)
            } else {
                report.failedApps.append(appName)
            }
        }
    }

    private static func pauseNetEaseMusic(into report: inout BackgroundMediaEnforcementReport, includeInactiveDiagnostics: Bool) {
        guard let app = runningNetEaseApplication() else {
            if includeInactiveDiagnostics {
                report.notes.append("网易云音乐未运行；\(installedNetEaseDiagnosticText())")
            }
            return
        }
        report.attemptedApps.append("网易云音乐")
        guard isAccessibilityTrustedForSpecialPlayerPause() else {
            report.skippedApps.append("网易云音乐")
            report.notes.append("网易云音乐需要辅助功能权限才能暂停")
            return
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        _ = AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        Thread.sleep(forTimeInterval: 0.15)
        // Only press a control explicitly labelled "暂停"/"Pause". While playing, the play/pause
        // control exposes the pause action; while paused it would read "播放", which we never press.
        if let button = findElement(in: appElement, matching: isPauseLabeledButton, maxNodes: 4000) {
            AXUIElementPerformAction(button, kAXPressAction as CFString)
            report.pausedApps.append("网易云音乐")
        } else if pauseNetEaseViaControlsMenu(in: appElement) {
            report.pausedApps.append("网易云音乐")
        } else {
            report.skippedApps.append("网易云音乐")
            report.notes.append("网易云音乐未找到「暂停」控件（可能未在播放，或客户端版本不同）")
            logNetEaseButtonCandidates(in: appElement)
            logNetEaseMenuCandidates(in: appElement)
        }
    }

    private static func runningNetEaseApplication() -> NSRunningApplication? {
        for identifier in netEaseBundleIdentifiers {
            if let app = runningApplication(bundleIdentifier: identifier) {
                return app
            }
        }
        return NSWorkspace.shared.runningApplications.first { app in
            guard let name = app.localizedName else { return false }
            return netEaseAppNames.contains(name)
        }
    }

    private static func installedNetEaseDiagnosticText() -> String {
        let installedApplications = netEaseBundleIdentifiers.compactMap { identifier -> String? in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) else {
                return nil
            }
            return "\(identifier)=\(url.path)"
        }
        if installedApplications.isEmpty {
            return "未通过已知 Bundle ID 找到已安装 App"
        }
        return "已安装：\(installedApplications.joined(separator: "、"))"
    }

    private static func isPauseLabeledButton(_ element: AXUIElement) -> Bool {
        guard stringAttribute("AXRole", of: element) == "AXButton" else { return false }
        let labels = [
            stringAttribute("AXTitle", of: element),
            stringAttribute("AXDescription", of: element)
        ].compactMap { $0 }
        return labels.contains { label in
            pauseControlLabels.contains { label == $0 || label.contains($0) }
        }
    }

    private static func pauseNetEaseViaControlsMenu(in appElement: AXUIElement) -> Bool {
        guard let pauseItem = netEaseControlsMenuItems(in: appElement).first(where: isPauseMenuItem) else {
            return false
        }
        AXUIElementPerformAction(pauseItem, kAXPressAction as CFString)
        return true
    }

    private static func netEaseControlsMenuItems(in appElement: AXUIElement) -> [AXUIElement] {
        var menuBarValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXMenuBarAttribute as CFString, &menuBarValue)
        guard result == .success, let menuBarValue else { return [] }
        let menuBar = menuBarValue as! AXUIElement
        guard let controlsMenu = children(of: menuBar).first(where: isNetEaseControlsMenu) else { return [] }
        let menuChildren = children(of: controlsMenu)
        let nestedItems = menuChildren.flatMap(children(of:))
        return nestedItems.isEmpty ? menuChildren : nestedItems
    }

    private static func isNetEaseControlsMenu(_ element: AXUIElement) -> Bool {
        guard stringAttribute("AXRole", of: element) == "AXMenuBarItem" else { return false }
        let title = stringAttribute("AXTitle", of: element) ?? ""
        return title == "Controls" || title == "控制"
    }

    private static func isPauseMenuItem(_ element: AXUIElement) -> Bool {
        guard stringAttribute("AXRole", of: element) == "AXMenuItem" else { return false }
        guard let title = stringAttribute("AXTitle", of: element) else { return false }
        return pauseControlLabels.contains { title == $0 || title.contains($0) }
    }

    /// One-off diagnostic: log button roles/titles/descriptions so an unmatched control can be targeted later.
    private static func logNetEaseButtonCandidates(in root: AXUIElement) {
        var queue = [root]
        var index = 0
        var visited = 0
        var candidates: [String] = []
        while index < queue.count, visited < 4000 {
            let element = queue[index]
            index += 1
            visited += 1
            if stringAttribute("AXRole", of: element) == "AXButton" {
                let title = diagnosticAttribute("AXTitle", of: element)
                let desc = diagnosticAttribute("AXDescription", of: element)
                let identifier = diagnosticAttribute("AXIdentifier", of: element)
                let roleDescription = diagnosticAttribute("AXRoleDescription", of: element)
                let help = diagnosticAttribute("AXHelp", of: element)
                let value = diagnosticAttribute("AXValue", of: element)
                if !(title.isEmpty && desc.isEmpty && identifier.isEmpty && roleDescription.isEmpty && help.isEmpty && value.isEmpty) {
                    candidates.append("[title=\(title) desc=\(desc) id=\(identifier) roleDesc=\(roleDescription) help=\(help) value=\(value)]")
                }
            }
            queue.append(contentsOf: children(of: element))
        }
        let joined = candidates.isEmpty ? "none" : candidates.prefix(40).joined(separator: " ")
        print("[DrinkingProject] netease_buttons \(joined)")
    }

    private static func logNetEaseMenuCandidates(in appElement: AXUIElement) {
        let candidates = netEaseControlsMenuItems(in: appElement).map { item in
            "[title=\(diagnosticAttribute("AXTitle", of: item)) role=\(diagnosticAttribute("AXRole", of: item)) enabled=\(diagnosticAttribute("AXEnabled", of: item))]"
        }
        let joined = candidates.isEmpty ? "none" : candidates.prefix(40).joined(separator: " ")
        print("[DrinkingProject] netease_menu_items \(joined)")
    }

    private static func pauseWeReadMedia(into report: inout BackgroundMediaEnforcementReport) {
        guard let app = runningApplication(bundleIdentifier: weReadBundleIdentifier) else { return }
        guard isAccessibilityTrustedForSpecialPlayerPause() else {
            report.skippedApps.append("微信读书")
            report.notes.append("微信读书需要辅助功能权限才能暂停")
            return
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        report.attemptedApps.append("微信读书")
        guard let firstElapsedSeconds = weReadElapsedSeconds(in: appElement) else {
            report.skippedApps.append("微信读书")
            report.notes.append("微信读书当前未检测到播放进度")
            return
        }
        Thread.sleep(forTimeInterval: 1.1)
        guard
            let secondElapsedSeconds = weReadElapsedSeconds(in: appElement),
            secondElapsedSeconds > firstElapsedSeconds
        else {
            report.skippedApps.append("微信读书")
            report.notes.append("微信读书当前未在播放")
            return
        }
        pressWeReadPlayButton(in: appElement)
        report.pausedApps.append("微信读书")
    }

    private static func isRunning(_ appName: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains { app in
            app.localizedName == appName
                || app.bundleURL?.deletingPathExtension().lastPathComponent == appName
        }
    }

    private static func isRunning(bundleIdentifier: String) -> Bool {
        runningApplication(bundleIdentifier: bundleIdentifier) != nil
    }

    private static func runningApplication(bundleIdentifier: String) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { app in
            app.bundleIdentifier == bundleIdentifier
        }
    }

    private static func isAccessibilityTrustedForSpecialPlayerPause() -> Bool {
        // Normal reminder/background checks must be read-only. Prompting is intentionally
        // routed through SettingsView's "打开系统设置 · 辅助功能" button so macOS is not asked
        // for Accessibility consent in a loop during launches or scheduled reminders.
        AXIsProcessTrusted()
    }

    private static func weReadElapsedSeconds(in root: AXUIElement) -> Int? {
        findElement(in: root) { element in
            elapsedSeconds(from: stringAttributes(of: element)) != nil
        }.flatMap { element in
            elapsedSeconds(from: stringAttributes(of: element))
        }
    }

    private static func pressWeReadPlayButton(in root: AXUIElement) {
        guard let button = findElement(in: root, matching: isWeReadPlayButton) else { return }
        AXUIElementPerformAction(button, kAXPressAction as CFString)
    }

    private static func isWeReadPlayButton(_ element: AXUIElement) -> Bool {
        stringAttribute("AXRole", of: element) == "AXButton"
            && stringAttribute("AXIdentifier", of: element) == weReadPlayButtonIdentifier
    }

    private static func findElement(
        in root: AXUIElement,
        matching predicate: (AXUIElement) -> Bool,
        maxNodes: Int = 500
    ) -> AXUIElement? {
        var queue = [root]
        var index = 0
        var visitedCount = 0
        while index < queue.count, visitedCount < maxNodes {
            let element = queue[index]
            index += 1
            visitedCount += 1
            if predicate(element) {
                return element
            }
            queue.append(contentsOf: children(of: element))
        }
        return nil
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, "AXChildren" as CFString, &value)
        guard result == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    private static func stringAttributes(of element: AXUIElement) -> [String] {
        ["AXDescription", "AXValue", "AXTitle", "AXIdentifier"].compactMap { attribute in
            stringAttribute(attribute, of: element)
        }
    }

    private static func stringAttribute(_ attribute: String, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else { return nil }
        return value as? String
    }

    private static func diagnosticAttribute(_ attribute: String, of element: AXUIElement) -> String {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success, let value else { return "" }
        if let string = value as? String {
            return string
        }
        return String(describing: value)
    }

    private static func elapsedSeconds(from values: [String]) -> Int? {
        for value in values {
            guard let firstPart = value.split(separator: "/").first else { continue }
            let timeText = firstPart.trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = timeText.split(separator: ":")
            guard
                parts.count == 2,
                let minutes = Int(parts[0]),
                let seconds = Int(parts[1])
            else {
                continue
            }
            return minutes * 60 + seconds
        }
        return nil
    }

    @discardableResult
    private static func runAppleScript(_ source: String) -> Bool {
        guard let appleScript = NSAppleScript(source: source) else { return false }
        var error: NSDictionary?
        appleScript.executeAndReturnError(&error)
        return error == nil
    }

    private static func runAppleScriptReturningString(_ source: String) -> AppleScriptStringResult {
        guard let appleScript = NSAppleScript(source: source) else {
            return .failure("AppleScript 无法创建")
        }
        var error: NSDictionary?
        let descriptor = appleScript.executeAndReturnError(&error)
        if let error {
            let message = error[NSAppleScript.errorMessage] as? String ?? String(describing: error)
            let number = error[NSAppleScript.errorNumber] as? Int
            if let number {
                return .failure("\(number): \(message)")
            }
            return .failure(message)
        }
        return .success(descriptor.stringValue ?? "")
    }
}
