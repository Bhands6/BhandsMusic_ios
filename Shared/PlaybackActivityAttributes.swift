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
        /// 平台约束（2026-10 逐帧截图实证）：实时活动只在收到内容更新时才
        /// 重渲染，且本地 update 有隐形配额 —— 所以 App 侧**只做事件级推送**
        /// （切歌 / 播放暂停 / 拖拽结束），会走的时间部件全部用系统自走视图
        /// （`ProgressView(timerInterval:)` / `Text(timerInterval:)`）。
        /// `(elapsed, timestamp)` 是它们的墙钟锚点：本曲开始 = timestamp − elapsed。
        var timestamp: Date

        /// 会话播放钟 —— 灵动岛动画（封面旋转 / 竖条）的唯一相位源。
        ///
        /// `playClock` = 本次播放段开始**之前**本会话累计播放的秒数；
        /// `playingSince` = 当前播放段的开始时刻（nil = 暂停中）。
        /// Widget 侧实时相位 = playClock + (now − playingSince)。
        /// 刻意**不**锚定每首歌的播放位置 —— 那样切歌、拖进度条都会让
        /// 旋转角度和竖条相位归零跳变。会话钟只有播放/暂停会拨动，
        /// 「切歌不影响动画」就是这么来的。
        var playClock: Double
        var playingSince: Date?

        /// 动画定格相位。非 nil 时封面旋转角 = freezePhase × 72°、
        /// 竖条相位 = freezePhase × 3.1 —— 不再跟随会话播放钟。
        ///
        /// 平台约束（2026-10 日志 + 连拍实证）：单个活动只有约 215~260 次
        /// 按秒渲染的预算，耗尽后系统把渲染合并成**精确 15.0 秒一帧**，且
        /// SwiftUI 补间时长被钳制在 ~3 秒 —— 15 秒跨帧连续动画物理上不可能，
        /// 强行补间只会得到「快转几圈再定格」。所以 App 侧在第 ~190 次推送时
        /// 主动定格：定格值 = 当时瞄准中的目标相位，正在播放的最后一帧补间
        /// 恰好滑入定格值 —— **零跳变**。换歌时若预算已耗尽会重开新活动
        /// （新预算），定格解除、动画恢复。
        var freezePhase: Double?

        var isLive: Bool { duration <= 0 }
        var remaining: Double { max(duration - elapsed, 0) }
    }

    /// 这里**不再放 songKey** —— 一个活动贯穿整个播放会话，
    /// 按歌变化的身份信息没有意义（按歌建活动会踩后台不能 request 的坑）。
    /// 属性留空即可，所有会变的东西都在 `ContentState` 里。
}
