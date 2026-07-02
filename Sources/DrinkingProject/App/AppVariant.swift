import Foundation

/// Identity of a build variant. Lets the new test build run side by side with the
/// original ("default") build without sharing data, LaunchAgent, menu title or
/// management window. When no `--variant` argument is passed, everything resolves
/// to `.standard` and behaves exactly like the original app.
struct AppVariant: Equatable {
    /// Stable identifier, e.g. "default" or "claude". Passed through launch args.
    let id: String
    /// Human readable name shown in Finder/Dock/Info.plist.
    let displayName: String
    /// Menu bar status item title.
    let statusItemTitle: String
    /// Folder name used under ~/Library/Application Support/.
    let appSupportFolderName: String
    /// LaunchAgent label / plist file base name.
    let launchAgentLabel: String
    /// Title used for the management window (kept distinct so old/new don't collide).
    let managementWindowTitle: String

    var isDefault: Bool { id == "default" }

    static let standard = AppVariant(
        id: "default",
        displayName: "Drinking Project",
        statusItemTitle: "水",
        appSupportFolderName: "Drinking Project",
        launchAgentLabel: "com.local.drinkingproject",
        managementWindowTitle: "Drinking Project"
    )

    static let claude = AppVariant(
        id: "claude",
        displayName: "Drinking Project",
        statusItemTitle: "水²",
        appSupportFolderName: "Drinking Project 2 Claude",
        launchAgentLabel: "com.local.drinkingproject.claude",
        managementWindowTitle: "Drinking Project"
    )

    /// Resolve the active variant from process launch arguments.
    /// `--variant claude` selects the test build; anything else is the default build.
    static func resolve(arguments: [String]) -> AppVariant {
        guard
            let index = arguments.firstIndex(of: "--variant"),
            arguments.indices.contains(index + 1)
        else {
            return .standard
        }
        switch arguments[index + 1] {
        case "claude":
            return .claude
        default:
            return .standard
        }
    }
}
