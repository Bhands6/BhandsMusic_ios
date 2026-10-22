import AppIntents
import Foundation

struct TogglePlaybackIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "播放或暂停"
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(PlaybackCommand.togglePlayback as CFString),
            nil,
            nil,
            true
        )
        return .result()
    }
}
