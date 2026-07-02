import Foundation

struct ReminderConfiguration {
    var lockSeconds: Int
    var requiredConfirmations: Int
    var confirmationCooldownSeconds: Int
    var playbackMode: VideoPlaybackMode
    var isPlaygroundMode: Bool
    var friendlyMessage: String
    var windowStyle: ReminderWindowStyle

    static func make(
        rule: ReminderRule,
        playbackMode: VideoPlaybackMode,
        isManual: Bool,
        playgroundModeEnabled: Bool,
        friendlyMessage: String,
        windowStyle: ReminderWindowStyle
    ) -> ReminderConfiguration {
        let usePlayground = isManual && playgroundModeEnabled
        return ReminderConfiguration(
            lockSeconds: usePlayground ? min(rule.lockSeconds, 3) : rule.lockSeconds,
            requiredConfirmations: usePlayground ? 1 : rule.requiredConfirmations,
            confirmationCooldownSeconds: usePlayground ? min(rule.confirmationCooldownSeconds, 1) : rule.confirmationCooldownSeconds,
            playbackMode: playbackMode,
            isPlaygroundMode: usePlayground,
            friendlyMessage: friendlyMessage,
            windowStyle: windowStyle
        )
    }
}
