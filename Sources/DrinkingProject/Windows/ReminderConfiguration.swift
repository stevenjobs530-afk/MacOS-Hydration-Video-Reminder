import Foundation

struct ReminderConfiguration {
    var lockSeconds: Int
    var requiredConfirmations: Int
    var confirmationCooldownSeconds: Int
    var playbackMode: VideoPlaybackMode
}
