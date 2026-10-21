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

        var isLive: Bool { duration <= 0 }
    }

    /// 一首歌对应一个活动。切歌时结束旧的、开新的 ——
    /// 比复用同一个活动再改内容简单，灵动岛也不会残留上一首的动画。
    var songKey: String
}
