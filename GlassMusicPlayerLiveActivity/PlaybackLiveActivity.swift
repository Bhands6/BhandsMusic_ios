import SwiftUI
import WidgetKit

/// 实时活动：锁屏卡片 + 灵动岛。
///
/// 只做**信息展示**，不放播放控制按钮 ——
/// Live Activity 跑在独立进程里，碰不到 App 的 AVPlayer；
/// 真要控制得走 AppIntent + 共享存储，那是另一套东西。
/// 播放控制在锁屏的「正在播放」卡片上（系统那套，见 AudioEngine）。
struct PlaybackLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PlaybackActivityAttributes.self) { context in
            lockScreenCard(context.state)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)

        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.isPlaying ? "waveform" : "pause.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.purple)
                        .symbolEffect(.variableColor.iterative, isActive: context.state.isPlaying)
                        .padding(.leading, 4)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.isLive ? "直播" : timeText(context.state.duration - context.state.elapsed))
                        .font(.system(size: 13, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 4)
                }

                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(context.state.title)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1)
                        Text(context.state.artist)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    progressBar(context.state)
                        .padding(.horizontal, 4)
                        .padding(.top, 2)
                }

            } compactLeading: {
                Image(systemName: context.state.isPlaying ? "waveform" : "pause.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.purple)

            } compactTrailing: {
                // 灵动岛紧凑态只有 ~44pt 宽，放个进度条比放文字直观
                if context.state.isLive {
                    Text("LIVE")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.purple)
                } else {
                    progressBar(context.state, height: 3)
                        .frame(width: 34)
                }

            } minimal: {
                Image(systemName: "waveform")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.purple)
            }
            .keylineTint(.purple)
        }
    }

    // MARK: - 锁屏卡片

    private func lockScreenCard(_ state: PlaybackActivityAttributes.ContentState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.42, green: 0.36, blue: 0.98),
                                         Color(red: 0.28, green: 0.20, blue: 0.72)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: state.isPlaying ? "waveform" : "pause.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.95))
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 2) {
                    Text(state.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(state.artist)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: state.isPlaying ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
            }

            progressBar(state)
        }
        .padding(14)
        .widgetURL(URL(string: "bhandsmusic://nowplaying"))
    }

    // MARK: - 零件

    @ViewBuilder
    private func progressBar(_ state: PlaybackActivityAttributes.ContentState, height: CGFloat = 4) -> some View {
        if state.isLive {
            Capsule()
                .fill(.white.opacity(0.18))
                .frame(height: height)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(.purple)
                        .frame(width: 28, height: height)
                }
        } else {
            // 用 timerInterval 让系统自己走，不用每秒 update
            ProgressView(
                timerInterval: Date().addingTimeInterval(-state.elapsed)...Date().addingTimeInterval(state.duration - state.elapsed),
                countsDown: false
            )
            .progressViewStyle(.linear)
            .tint(.purple)
            .scaleEffect(y: height / 4, anchor: .center)
        }
    }

    private func timeText(_ seconds: Double) -> String {
        let value = max(0, Int(seconds.rounded()))
        return String(format: "-%d:%02d", value / 60, value % 60)
    }
}
