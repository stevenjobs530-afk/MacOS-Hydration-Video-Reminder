import Foundation

enum VideoPlaybackMode: String, Codable, CaseIterable, Identifiable {
    case advanceOnEnd
    case loopSelected

    var id: String { rawValue }

    var title: String {
        switch self {
        case .advanceOnEnd:
            return "播完换下一个"
        case .loopSelected:
            return "单条循环"
        }
    }
}

struct AppSettings: Codable, Equatable {
    var remindersEnabled: Bool
    var playbackMode: VideoPlaybackMode
    var reminderVolume: Double
    var launchAtLoginEnabled: Bool
    var pausedDate: String?

    static let defaults = AppSettings(
        remindersEnabled: true,
        playbackMode: .advanceOnEnd,
        reminderVolume: 15,
        launchAtLoginEnabled: false,
        pausedDate: nil
    )
}
