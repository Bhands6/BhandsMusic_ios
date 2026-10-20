import SwiftUI

/// 播放列表详情 —— 大封面随滚动收合，标题在悬浮头部淡入。
struct PlaylistDetailView: View {
    let playlist: Playlist

    @Environment(PlayerModel.self) private var player
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var scrollOffset: CGFloat = 0

    private var songs: [Song] { MusicLibrary.songs }

    /// 滚动 0…260 时，封面从 1 缩到 0.72
    private var coverScale: CGFloat {
        let progress = min(max(scrollOffset / 260, 0), 1)
        return 1 - progress * 0.28
    }

    private var coverOpacity: Double {
        let progress = min(max(scrollOffset / 200, 0), 1)
        return 1 - Double(progress) * 0.75
    }

    var body: some View {
        ZStack(alignment: .top) {
            SoftCanvas()

            ScrollView {
                VStack(spacing: LiquidTheme.Spacing.lg) {
                    coverHeader
                    actions
                    trackList
                    meta
                }
                .padding(.top, 56)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .readScrollOffset(into: $scrollOffset)

            ScreenHeader(
                title: playlist.title,
                scrollOffset: scrollOffset,
                showsBack: true,
                onBack: { dismiss() }
            ) {
                HeaderIconButton(systemName: "ellipsis") {}
            }
            .padding(.horizontal, LiquidTheme.Spacing.md)
            .padding(.top, 4)
        }
    }

    // MARK: - 封面

    private var coverHeader: some View {
        VStack(spacing: LiquidTheme.Spacing.md) {
            PlaylistCover(playlist: playlist, cornerRadius: LiquidTheme.Radius.card, symbolSize: 52)
                .frame(width: 208, height: 208)
                .scaleEffect(coverScale)
                .opacity(coverOpacity)
                .shadow(color: .black.opacity(0.18), radius: 24, y: 12)

            VStack(spacing: 6) {
                Text(playlist.title)
                    .font(LiquidTheme.Typography.screen)
                    .foregroundStyle(LiquidTheme.Palette.label)
                    .multilineTextAlignment(.center)

                Text(playlist.subtitle)
                    .font(LiquidTheme.Typography.rowMeta)
                    .foregroundStyle(LiquidTheme.Palette.secondary)
                    .multilineTextAlignment(.center)

                Text("\(playlist.count) 首 · \(totalDuration)")
                    .font(LiquidTheme.Typography.caption)
                    .foregroundStyle(LiquidTheme.Palette.tertiary)
            }
            .opacity(coverOpacity)
            .padding(.horizontal, LiquidTheme.Spacing.screenH)
        }
    }

    private var totalDuration: String {
        let seconds = songs.reduce(0) { $0 + $1.duration }
        let minutes = Int(seconds / 60)
        return minutes >= 60 ? "\(minutes / 60) 小时 \(minutes % 60) 分" : "\(minutes) 分钟"
    }

    // MARK: - 操作

    private var actions: some View {
        HStack(spacing: LiquidTheme.Spacing.sm) {
            Button {
                if let first = songs.first { player.play(first, in: songs) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("播放")
                        .font(LiquidTheme.Typography.button)
                }
                .foregroundStyle(LiquidTheme.Palette.onAccent)
                .frame(maxWidth: .infinity)
                .frame(height: LiquidTheme.Hit.control)
                .background(Capsule().fill(LiquidTheme.Palette.accent))
            }
            .buttonStyle(.plain)

            Button {
                if let random = songs.randomElement() {
                    player.isShuffleOn = true
                    player.play(random, in: songs)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "shuffle")
                        .font(.system(size: 14, weight: .semibold))
                    Text("随机播放")
                        .font(LiquidTheme.Typography.button)
                }
                .foregroundStyle(LiquidTheme.Palette.label)
                .frame(maxWidth: .infinity)
                .frame(height: LiquidTheme.Hit.control)
                .liquidGlassCapsule(interactive: true)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, LiquidTheme.Spacing.screenH)
    }

    // MARK: - 曲目

    private var trackList: some View {
        VStack(spacing: 0) {
            ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                if index > 0 {
                    Rectangle()
                        .fill(LiquidTheme.Palette.separator.opacity(0.5))
                        .frame(height: 0.5)
                        .padding(.leading, 78)
                }

                SongRow(
                    song: song,
                    index: index + 1,
                    isCurrent: song.id == player.current.id,
                    isPlaying: player.isPlaying,
                    isLiked: player.isLiked(song)
                ) {
                    player.play(song, in: songs)
                }
            }
        }
        .glassPanel()
        .padding(.horizontal, LiquidTheme.Spacing.screenH)
    }

    private var meta: some View {
        VStack(spacing: 2) {
            Text("由 BhandsMusic 编辑部制作")
                .font(LiquidTheme.Typography.caption)
                .foregroundStyle(LiquidTheme.Palette.secondary)
            Text("每周一更新")
                .font(LiquidTheme.Typography.caption)
                .foregroundStyle(LiquidTheme.Palette.tertiary)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    PlaylistDetailView(playlist: MusicLibrary.playlists[0])
        .environment(PlayerModel())
}
