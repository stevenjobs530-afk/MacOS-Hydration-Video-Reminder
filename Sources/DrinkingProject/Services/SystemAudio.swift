import AppKit

enum SystemAudio {
    static func setOutputVolume(to percent: Int) {
        let clamped = max(0, min(100, percent))
        let script = "set volume output volume \(clamped)"
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }
}
