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
    var playgroundModeEnabled: Bool

    static let defaults = AppSettings(
        remindersEnabled: true,
        playbackMode: .advanceOnEnd,
        reminderVolume: 15,
        launchAtLoginEnabled: false,
        pausedDate: nil,
        playgroundModeEnabled: false
    )

    init(
        remindersEnabled: Bool,
        playbackMode: VideoPlaybackMode,
        reminderVolume: Double,
        launchAtLoginEnabled: Bool,
        pausedDate: String?,
        playgroundModeEnabled: Bool
    ) {
        self.remindersEnabled = remindersEnabled
        self.playbackMode = playbackMode
        self.reminderVolume = reminderVolume
        self.launchAtLoginEnabled = launchAtLoginEnabled
        self.pausedDate = pausedDate
        self.playgroundModeEnabled = playgroundModeEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case remindersEnabled
        case playbackMode
        case reminderVolume
        case launchAtLoginEnabled
        case pausedDate
        case playgroundModeEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Self.defaults
        remindersEnabled = try container.decodeIfPresent(Bool.self, forKey: .remindersEnabled) ?? fallback.remindersEnabled
        playbackMode = try container.decodeIfPresent(VideoPlaybackMode.self, forKey: .playbackMode) ?? fallback.playbackMode
        reminderVolume = try container.decodeIfPresent(Double.self, forKey: .reminderVolume) ?? fallback.reminderVolume
        launchAtLoginEnabled = try container.decodeIfPresent(Bool.self, forKey: .launchAtLoginEnabled) ?? fallback.launchAtLoginEnabled
        pausedDate = try container.decodeIfPresent(String.self, forKey: .pausedDate)
        playgroundModeEnabled = try container.decodeIfPresent(Bool.self, forKey: .playgroundModeEnabled) ?? fallback.playgroundModeEnabled
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(remindersEnabled, forKey: .remindersEnabled)
        try container.encode(playbackMode, forKey: .playbackMode)
        try container.encode(reminderVolume, forKey: .reminderVolume)
        try container.encode(launchAtLoginEnabled, forKey: .launchAtLoginEnabled)
        try container.encodeIfPresent(pausedDate, forKey: .pausedDate)
        try container.encode(playgroundModeEnabled, forKey: .playgroundModeEnabled)
    }
}
