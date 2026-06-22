import ApplicationServices
import AppKit

enum BackgroundMediaControl {
    private static let weReadBundleIdentifier = "com.tencent.weread"
    private static let weReadPlayButtonIdentifier = "ViewID_PlayerToolBarPlay"

    static func pauseLikelyMediaSources() {
        pauseBrowserMedia()
        pauseKnownPlayerApps()
        pauseWeReadMedia()
    }

    private static func pauseBrowserMedia() {
        let pauseScript = "(function(){var pause=function(root){root.querySelectorAll('video,audio').forEach(function(media){try{media.pause();}catch(e){}});};try{pause(document);}catch(e){}document.querySelectorAll('iframe').forEach(function(frame){try{if(frame.contentDocument){pause(frame.contentDocument);}}catch(e){}});}());"
        let browsers = [
            ("Safari", "do JavaScript \"\(pauseScript)\" in browserTab"),
            ("Google Chrome", "execute browserTab javascript \"\(pauseScript)\""),
            ("Microsoft Edge", "execute browserTab javascript \"\(pauseScript)\""),
            ("Brave Browser", "execute browserTab javascript \"\(pauseScript)\""),
            ("Arc", "execute browserTab javascript \"\(pauseScript)\""),
            ("Vivaldi", "execute browserTab javascript \"\(pauseScript)\""),
            ("Opera", "execute browserTab javascript \"\(pauseScript)\"")
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
        // Use explicit pause commands only. Play/pause media-key toggles can restart paused media.
        let scriptsByAppName = [
            "Music": #"tell application "Music" to pause"#,
            "TV": #"tell application "TV" to pause"#,
            "Spotify": #"tell application "Spotify" to pause"#,
            "Podcasts": #"tell application "Podcasts" to pause"#,
            "QuickTime Player": #"tell application "QuickTime Player" to pause every document"#,
            "IINA": #"tell application "IINA" to pause"#,
            "VLC": #"tell application "VLC" to pause"#,
            "Elmedia Player": #"tell application "Elmedia Player" to pause"#,
            "网易云音乐": #"tell application "网易云音乐" to pause"#,
            "NetEaseMusic": #"tell application "NetEaseMusic" to pause"#,
            "NeteaseMusic": #"tell application "NeteaseMusic" to pause"#,
            "NetEase Cloud Music": #"tell application "NetEase Cloud Music" to pause"#,
            "微信读书": #"tell application "微信读书" to pause"#,
            "WeRead": #"tell application "WeRead" to pause"#
        ]

        for (appName, script) in scriptsByAppName where isRunning(appName) {
            runAppleScript(script)
        }
    }

    private static func pauseWeReadMedia() {
        guard let app = runningApplication(bundleIdentifier: weReadBundleIdentifier) else { return }
        guard isAccessibilityTrustedForWeReadPause() else { return }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let firstElapsedSeconds = weReadElapsedSeconds(in: appElement) else { return }
        Thread.sleep(forTimeInterval: 1.1)
        guard
            let secondElapsedSeconds = weReadElapsedSeconds(in: appElement),
            secondElapsedSeconds > firstElapsedSeconds
        else {
            return
        }
        pressWeReadPlayButton(in: appElement)
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

    private static func isAccessibilityTrustedForWeReadPause() -> Bool {
        if AXIsProcessTrusted() {
            return true
        }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        return false
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
        matching predicate: (AXUIElement) -> Bool
    ) -> AXUIElement? {
        var queue = [root]
        var index = 0
        var visitedCount = 0
        while index < queue.count, visitedCount < 500 {
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

    private static func runAppleScript(_ source: String) {
        guard let appleScript = NSAppleScript(source: source) else { return }
        var error: NSDictionary?
        appleScript.executeAndReturnError(&error)
    }
}
