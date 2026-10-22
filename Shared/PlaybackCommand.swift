import Foundation

/// Live Activity Intent 与主 App 之间的跨进程播放命令。
///
/// 播放器在主 App 的后台音频进程中运行。Widget 扩展不能直接访问 AVPlayer，
/// 因此只投递一个 Darwin 通知，由主 App 真正切换播放状态。
enum PlaybackCommand {
    static let togglePlayback = "com.example.GlassMusicPlayer.togglePlayback"
}
