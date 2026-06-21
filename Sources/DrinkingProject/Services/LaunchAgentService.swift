import Foundation

enum LaunchAgentService {
    static let label = "com.local.drinkingproject"

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }
}
