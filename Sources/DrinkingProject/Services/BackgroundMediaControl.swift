import AppKit
import IOKit

enum BackgroundMediaControl {
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
