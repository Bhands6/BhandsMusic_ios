import ActivityKit
import Foundation

/// 实时活动（锁屏卡片 + 灵动岛）的数据模型。
///
/// ⚠️ 这个文件**同时属于 App 和 Widget Extension 两个 target** ——
/// ActivityKit 靠类型名在进程间匹配，两边必须是同一份定义。
/// 改的时候记得两个 target 都会编到（工程里 Shared/ 文件夹挂在两个 target 下）。
struct PlaybackActivityAttributes: ActivityAttributes {

    /// 会随时间变化的部分。`title`/`artist` 不变，但一起放这里更省事 ——
    /// 每次更新都要整体重发一份。
    struct ContentState: Codable, Hashable {
        var title: String
        var artist: String
        var isPlaying: Bool
        /// 已播秒数
        var elapsed: Double
        /// 总时长。直播流是 0
        var duration: Double
        /// 封面（JPEG 数据，App 侧已缩到 48px 并压到 1800 字节以内）。
        /// Widget 扩展没有网络权限也拿不到 App 的图片缓存，只能随状态塞进来。
        /// nil 时 Widget 画渐变兜底。
        var artworkData: Data?
        /// 捕获 `elapsed` 的那一瞬间。
        ///
        /// 只用于进度条和倒计时的锚点。
        var timestamp: Date
        /// 只驱动 compact 音量条的本地补间，不代表音频采样数据。
        var motionPhase: Double
        /// 每次推送严格递增，作为 SwiftUI 补间的触发键。
        var pushID: UInt64

        var isLive: Bool { duration <= 0 }
        var remaining: Double { max(duration - elapsed, 0) }
    }

    /// 这里**不再放 songKey** —— 一个活动贯穿整个播放会话，
    /// 按歌变化的身份信息没有意义（按歌建活动会踩后台不能 request 的坑）。
    /// 属性留空即可，所有会变的东西都在 `ContentState` 里。
}
