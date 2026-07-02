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

enum ReminderScreenMode: String, Codable, CaseIterable, Identifiable {
    case allScreens
    case mainOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allScreens:
            return "覆盖所有屏幕"
        case .mainOnly:
            return "仅主屏幕"
        }
    }
}

enum ReminderWindowStyle: String, Codable, CaseIterable, Identifiable {
    case fullScreenVideo
    case compactPopup

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fullScreenVideo:
            return "全屏视频提醒"
        case .compactPopup:
            return "Mac 弹窗提醒（不播视频）"
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
    var reminderScreenMode: ReminderScreenMode
    var reminderWindowStyle: ReminderWindowStyle

    static let defaults = AppSettings(
        remindersEnabled: true,
        playbackMode: .advanceOnEnd,
        reminderVolume: 15,
        launchAtLoginEnabled: false,
        pausedDate: nil,
        playgroundModeEnabled: false,
        reminderScreenMode: .allScreens,
        reminderWindowStyle: .fullScreenVideo
    )

    init(
        remindersEnabled: Bool,
        playbackMode: VideoPlaybackMode,
        reminderVolume: Double,
        launchAtLoginEnabled: Bool,
        pausedDate: String?,
        playgroundModeEnabled: Bool,
        reminderScreenMode: ReminderScreenMode,
        reminderWindowStyle: ReminderWindowStyle
    ) {
        self.remindersEnabled = remindersEnabled
        self.playbackMode = playbackMode
        self.reminderVolume = reminderVolume
        self.launchAtLoginEnabled = launchAtLoginEnabled
        self.pausedDate = pausedDate
        self.playgroundModeEnabled = playgroundModeEnabled
        self.reminderScreenMode = reminderScreenMode
        self.reminderWindowStyle = reminderWindowStyle
    }

    private enum CodingKeys: String, CodingKey {
        case remindersEnabled
        case playbackMode
        case reminderVolume
        case launchAtLoginEnabled
        case pausedDate
        case playgroundModeEnabled
        case reminderScreenMode
        case reminderWindowStyle
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
        reminderScreenMode = try container.decodeIfPresent(ReminderScreenMode.self, forKey: .reminderScreenMode) ?? fallback.reminderScreenMode
        reminderWindowStyle = try container.decodeIfPresent(ReminderWindowStyle.self, forKey: .reminderWindowStyle) ?? fallback.reminderWindowStyle
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(remindersEnabled, forKey: .remindersEnabled)
        try container.encode(playbackMode, forKey: .playbackMode)
        try container.encode(reminderVolume, forKey: .reminderVolume)
        try container.encode(launchAtLoginEnabled, forKey: .launchAtLoginEnabled)
        try container.encodeIfPresent(pausedDate, forKey: .pausedDate)
        try container.encode(playgroundModeEnabled, forKey: .playgroundModeEnabled)
        try container.encode(reminderScreenMode, forKey: .reminderScreenMode)
        try container.encode(reminderWindowStyle, forKey: .reminderWindowStyle)
    }

    var reminderAudioVolume: Float {
        Float(max(0.0, min(100.0, reminderVolume)) / 100.0)
    }
}
