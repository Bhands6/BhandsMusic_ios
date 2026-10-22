import ActivityKit
import AppIntents
import SwiftUI
import UIKit
import WidgetKit

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
                    CoverArt(state: context.state, diameter: 40, cornerRadius: 10)
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
                CoverArt(state: context.state, diameter: 30)
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                CoverArt(state: state, diameter: 48, cornerRadius: 12)
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
                // 竖条的运动**只靠本地墙钟**，不再依赖 App 推送的 motionPhase。
                // 进度条（timerInterval）和倒计时（TimelineView）本来就是本地自走，
                // 竖条是唯一绑在推送链上的动效 —— 推送一停（杀进程、后台挂起、
                // 更新被系统静默丢弃）整条岛就冻住，别的部件还在动，特别露馅。
                // 相位锚定最后一次推送捕获的播放位置（elapsed @ timestamp），
                // 与进度条同一时间基，推送断了节奏也不抢拍。
                TimelineView(.periodic(from: .now, by: 0.25)) { context in
                    let phase = Self.phase(
                        at: context.date,
                        elapsed: state.elapsed,
                        anchor: state.timestamp
                    )
                    HStack(alignment: .center, spacing: 2) {
                        ForEach(0..<3, id: \.self) { index in
                            Capsule()
                                .fill(Color(red: 0.95, green: 0.28, blue: 0.35))
                                .frame(width: 2.5, height: barHeight(at: index, phase: phase))
                        }
                    }
                    .frame(width: 16, height: 20)
                    .animation(.linear(duration: 0.25), value: phase)
                }
            }
        }
        .frame(width: 18, height: 20)
        .accessibilityHidden(true)
    }

    /// 墙钟 → 动画相位（弧度）。3.1 rad/s ≈ 2s 一个完整起伏周期，
    /// 和旧版按推送间隔累加 motionPhase 的节奏一致。
    static func phase(at date: Date, elapsed: Double, anchor: Date) -> Double {
        let played = elapsed + max(0, date.timeIntervalSince(anchor))
        return played * 3.1
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
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(durationText(max(state.remaining - context.date.timeIntervalSince(state.timestamp), 0)))
                        .font(labelFont)
                        .monospacedDigit()
                        .foregroundStyle(labelColor)
                }
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
