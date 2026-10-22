import ActivityKit
import AppIntents
import SwiftUI
import UIKit
import WidgetKit

/// 会话播放钟的实时值：累计段 + 当前播放段（按渲染时刻墙钟推进）。
/// 灵动岛动画（封面旋转 / 竖条）的唯一相位源 —— 刻意不锚定每首歌的
/// 播放位置，切歌、拖进度条都不会让它归零跳变。
extension PlaybackActivityAttributes.ContentState {
    var livePlaytime: Double {
        playClock + (playingSince.map { max(0, Date().timeIntervalSince($0)) } ?? 0)
    }
}

/// 补间窗口：动画目标瞄准「未来 N 秒」、补间时长同为 N —— 系统在两帧快照之间
/// 按此时长线性插值，N 与帧间隔一致时严格匀速（角度是时间的线性函数，
/// 1Hz 关键帧 + 1s 线性补间 = 完美匀速旋转；帧丢了相位也不漂，
/// 相位真源是会话播放钟）。
/// ⚠️ N 不能远大于帧间隔：曾用 3600s 给封面「零帧需求」，结果两帧间
/// 72° 的角度差被摊到 3600s 里（或被系统钳制时长），旋转变成卡顿。
/// 暂停帧：目标 = 当前位置且不补间 → 立即定格。
private let coverTweenWindow: Double = 1
private let barTweenWindow: Double = 1

struct PlaybackLiveActivity: Widget {
    private let deepLink = URL(string: "bhandsmusic://nowplaying")

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PlaybackActivityAttributes.self) { context in
            lockScreenCard(context.state)
                .activityBackgroundTint(Color.black.opacity(0.62))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(deepLink)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    let angle = (context.state.livePlaytime + coverTweenWindow) * 72
                    CoverArt(state: context.state, diameter: 40, cornerRadius: 10)
                        .rotationEffect(.degrees(angle))
                        .animation(
                            context.state.isPlaying ? .linear(duration: coverTweenWindow) : nil,
                            value: angle
                        )
                        .accessibilityHidden(true)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    RemainingLabel(state: context.state, style: .expanded)
                        .padding(.trailing, 4)
                }

                DynamicIslandExpandedRegion(.center) {
                    TrackMetadata(state: context.state, showsArtist: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 10) {
                        PlaybackToggleButton(isPlaying: context.state.isPlaying)
                        PlaybackProgress(state: context.state)
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 2)
                }
            } compactLeading: {
                let angle = (context.state.livePlaytime + coverTweenWindow) * 72
                CoverArt(state: context.state, diameter: 30)
                    .rotationEffect(.degrees(angle))
                    .animation(
                        context.state.isPlaying ? .linear(duration: coverTweenWindow) : nil,
                        value: angle
                    )
                    .accessibilityHidden(true)
            } compactTrailing: {
                CompactPlaybackStatus(state: context.state)
            } minimal: {
                MinimalPlaybackStatus(state: context.state)
            }
            .keylineTint(.purple)
            .widgetURL(deepLink)
        }
    }

    private func lockScreenCard(_ state: PlaybackActivityAttributes.ContentState) -> some View {
        let angle = (state.livePlaytime + coverTweenWindow) * 72
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                CoverArt(state: state, diameter: 48, cornerRadius: 12)
                    .rotationEffect(.degrees(angle))
                    .animation(
                        state.isPlaying ? .linear(duration: coverTweenWindow) : nil,
                        value: angle
                    )
                    .accessibilityHidden(true)

                TrackMetadata(state: state, showsArtist: true, light: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 4) {
                    PlaybackToggleButton(isPlaying: state.isPlaying, style: .lockScreen)
                    RemainingLabel(state: state, style: .lockScreen)
                }
            }

            PlaybackProgress(state: state)
        }
        .padding(14)
        .accessibilityElement(children: .contain)
    }
}

private struct TrackMetadata: View {
    let state: PlaybackActivityAttributes.ContentState
    var showsArtist = true
    var light = false

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(state.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(light ? Color.white : Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            if showsArtist {
                Text(state.artist)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(light ? Color.white.opacity(0.72) : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct CompactPlaybackStatus: View {
    let state: PlaybackActivityAttributes.ContentState

    var body: some View {
        PlaybackStateIcon(state: state)
            .frame(width: 22, height: 22)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(state.title)，\(state.isPlaying ? "正在播放" : "已暂停")")
    }
}

private struct MinimalPlaybackStatus: View {
    let state: PlaybackActivityAttributes.ContentState

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            CoverArt(state: state, diameter: 22)

            Circle()
                .fill(Color.black.opacity(0.88))
                .frame(width: 11, height: 11)
                .overlay {
                    Image(systemName: state.isPlaying ? "play.fill" : "pause.fill")
                        .font(.system(size: 5, weight: .bold))
                        .foregroundStyle(.white)
                }
        }
        .frame(width: 28, height: 28)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(state.title)，\(state.isPlaying ? "正在播放" : "已暂停")")
    }
}

private struct PlaybackStateIcon: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let state: PlaybackActivityAttributes.ContentState

    var body: some View {
        Group {
            if !state.isPlaying {
                Image(systemName: "pause.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.secondary)
            } else if reduceMotion {
                Image(systemName: "waveform")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(red: 0.95, green: 0.28, blue: 0.35))
            } else {
                // 竖条相位 = 会话播放钟 × 3.1 rad/s（≈2 秒一个起伏周期）。
                // aim-ahead：目标瞄准未来 1 秒的相位、补间 1 秒 —— 恒速起伏，
                // 与帧率无关；App 侧 1Hz 帧流负责持续重瞄准。
                // 相位真源是会话钟 —— 切歌、拖进度条都不打断起伏。
                // 暂停帧目标 = 当前相位且不补间 → 立即定格。
                let phase = (state.livePlaytime + barTweenWindow) * 3.1
                HStack(alignment: .center, spacing: 2) {
                    ForEach(0..<5, id: \.self) { index in
                        Capsule()
                            .fill(Color(red: 0.95, green: 0.28, blue: 0.35))
                            .frame(width: 2.5, height: barHeight(at: index, phase: phase))
                    }
                }
                .frame(height: 20)
                .animation(
                    state.isPlaying ? .linear(duration: barTweenWindow) : nil,
                    value: phase
                )
            }
        }
        .frame(height: 20)
        .accessibilityHidden(true)
    }

    private func barHeight(at index: Int, phase: Double) -> CGFloat {
        let wave = sin(phase + Double(index) * 1.35)
        return 10 + 5 * wave
    }
}

private struct RemainingLabel: View {
    enum Style {
        case compact
        case expanded
        case lockScreen
    }

    let state: PlaybackActivityAttributes.ContentState
    let style: Style

    var body: some View {
        Group {
            if state.isLive {
                Text("LIVE")
                    .font(labelFont)
                    .foregroundStyle(.purple)
            } else if state.isPlaying {
                // 倒计时按渲染时刻的墙钟从 (remaining, timestamp) 锚点算 ——
                // App 侧 1Hz 帧流每秒渲染一帧，走字靠帧。
                // ⚠️ 勿改回 Text(timerInterval:)：在 iOS 26 上会让渲染器
                // 崩溃（GeometryReaderLayout 布局断言，崩溃报告实锤），
                // 崩溃后岛只显示系统占位灰图标。
                Text(durationText(max(state.remaining - Date().timeIntervalSince(state.timestamp), 0)))
                    .font(labelFont)
                    .monospacedDigit()
                    .foregroundStyle(labelColor)
            } else {
                Text(durationText(state.remaining))
                    .font(labelFont)
                    .monospacedDigit()
                    .foregroundStyle(labelColor)
            }
        }
        .lineLimit(1)
        .fixedSize()
        .accessibilityHidden(true)
    }

    private var labelFont: Font {
        switch style {
        case .compact: return .caption2.weight(.semibold)
        case .expanded: return .caption.weight(.semibold)
        case .lockScreen: return .caption2.weight(.semibold)
        }
    }

    private var labelColor: Color {
        style == .lockScreen ? .white.opacity(0.72) : .secondary
    }

    private func durationText(_ seconds: Double) -> String {
        if style == .compact {
            if seconds < 60 { return "<1m" }
            return "\(Int(seconds / 60))m"
        }
        let value = max(0, Int(seconds.rounded()))
        return String(format: "-%d:%02d", value / 60, value % 60)
    }
}

private struct PlaybackToggleButton: View {
    enum Style {
        case expanded
        case lockScreen
    }

    let isPlaying: Bool
    var style: Style = .expanded

    var body: some View {
        Button(intent: TogglePlaybackIntent()) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: style == .lockScreen ? 36 : 34, height: style == .lockScreen ? 36 : 34)
                .background(Color.purple, in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPlaying ? "暂停" : "播放")
    }
}

private struct PlaybackProgress: View {
    let state: PlaybackActivityAttributes.ContentState

    var body: some View {
        if state.isLive {
            HStack(spacing: 6) {
                Circle()
                    .fill(.purple)
                    .frame(width: 6, height: 6)
                Text("直播")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .frame(height: 20)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("直播")
        } else {
            let start = state.timestamp.addingTimeInterval(-state.elapsed)
            let end = state.timestamp.addingTimeInterval(state.remaining)

            Group {
                if state.isPlaying {
                    ProgressView(timerInterval: start...end, countsDown: false)
                        .progressViewStyle(.linear)
                } else {
                    ProgressView(value: state.duration > 0 ? state.elapsed / state.duration : 0)
                        .progressViewStyle(.linear)
                }
            }
            .tint(.purple)
            .scaleEffect(y: 1.25, anchor: .center)
            .accessibilityLabel("播放进度")
            .accessibilityValue("\(Int((state.duration > 0 ? state.elapsed / state.duration : 0) * 100))%")
        }
    }
}

private struct CoverArt: View {
    let state: PlaybackActivityAttributes.ContentState
    let diameter: CGFloat
    var cornerRadius: CGFloat?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.42, green: 0.36, blue: 0.98), Color(red: 0.28, green: 0.20, blue: 0.72)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: "music.note")
                .font(.system(size: diameter * 0.38, weight: .semibold))
                .foregroundStyle(.white.opacity(0.94))

            if let data = state.artworkData, let image = ArtworkCache.image(for: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            }
        }
        .frame(width: diameter, height: diameter)
        .clipShape(CircleOrRounded(radius: cornerRadius))
        .animation(.easeInOut(duration: 0.2), value: state.artworkData)
    }
}

private enum ArtworkCache {
    static let decoded: NSCache<NSData, UIImage> = {
        let cache = NSCache<NSData, UIImage>()
        cache.countLimit = 8
        return cache
    }()

    static func image(for data: Data) -> UIImage? {
        let key = data as NSData
        if let hit = decoded.object(forKey: key) { return hit }
        guard let image = UIImage(data: data) else { return nil }
        decoded.setObject(image, forKey: key)
        return image
    }
}

private struct CircleOrRounded: Shape {
    var radius: CGFloat?

    func path(in rect: CGRect) -> Path {
        if let radius {
            return Path(roundedRect: rect, cornerRadius: radius, style: .continuous)
        }
        return Path(ellipseIn: rect)
    }
}
