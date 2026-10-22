import AppIntents
import Foundation

/// 灵动岛 / 锁屏卡片上的播放暂停按钮。
///
/// `AudioPlaybackIntent`（iOS 18+）：App 被杀后这张卡还挂在锁屏上，
/// 用户仍可能去点它 —— 这个协议让系统把主 App 在**后台**拉起来执行
/// intent，Darwin 通知才有接收方，按钮不至于变成哑的。
/// App 活着时行为不变（后台音频本就让进程常驻）。
struct TogglePlaybackIntent: LiveActivityIntent, AudioPlaybackIntent {
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
