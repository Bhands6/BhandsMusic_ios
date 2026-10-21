import ActivityKit
import Foundation
import OSLog

/// 实时活动的生命周期。App 这边负责 start / update / end，扩展负责渲染。
///
/// 一个活动对应**一首歌**：切歌就结束旧的、开新的。
/// 复用同一个活动再改内容也能做，但灵动岛会残留上一首的收缩动画。
@MainActor
final class PlaybackActivityManager {

    static let shared = PlaybackActivityManager()

    private let log = Logger(subsystem: "com.bhands.glassmusicplayer", category: "LiveActivity")

    private var activity: Activity<PlaybackActivityAttributes>?
    private var currentKey: String?

    /// 系统设置里关掉实时活动时不要硬起
    private var isEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    func sync(
        title: String,
        artist: String,
        songKey: String,
        elapsed: Double,
        duration: Double,
        isPlaying: Bool
    ) {
        guard isEnabled else {
            log.notice("实时活动被系统禁用，跳过")
            return
        }

        let state = PlaybackActivityAttributes.ContentState(
            title: title,
            artist: artist,
            isPlaying: isPlaying,
            elapsed: elapsed,
            duration: duration
        )
        // 15 分钟后自动标记为过期，避免暂停后一直挂在锁屏上
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(900))

        // 换歌：结束旧的，开新的
        if let activity, currentKey != songKey {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
            self.activity = nil
            currentKey = nil
        }

        if let activity {
            Task { await activity.update(content) }
            return
        }

        do {
            activity = try Activity.request(
                attributes: PlaybackActivityAttributes(songKey: songKey),
                content: content
            )
            currentKey = songKey
        } catch {
            // 不影响播放，但要看得到原因 —— 之前静默吞掉，排查时两眼一抹黑
            log.error("实时活动启动失败: \(error.localizedDescription, privacy: .public)")
            activity = nil
        }
    }

    func end() {
        guard let activity else { return }
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
        self.activity = nil
        currentKey = nil
    }
}
