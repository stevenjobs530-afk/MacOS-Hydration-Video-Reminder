import AppKit

final class ReminderWindow: NSWindow {
    /// Invoked when the user presses Command+W to close the current reminder without
    /// quitting the app. The controller runs the same clean close flow as completion.
    var onCloseShortcut: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "q" {
            NSApp.terminate(nil)
            return
        }
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "w" {
            onCloseShortcut?()
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
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "w" {
            onCloseShortcut?()
            return true
        }
        if event.keyCode == 53 || event.modifierFlags.contains(.command) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
