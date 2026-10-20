import SwiftUI

/// 播放列表详情 —— 大封面随滚动收合，标题在悬浮头部淡入。
struct PlaylistDetailView: View {
    let playlist: Playlist

    @Environment(PlayerModel.self) private var player
    @Environment(PlaylistStore.self) private var playlists
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var scrollOffset: CGFloat = 0
    /// 点歌后自动打开「正在播放」。
    /// 用本视图自己的 cover 而不是复用根视图那个 —— 歌单是 sheet，
    /// 根视图的 fullScreenCover 在 sheet 之上是弹不出来的。
    /// 好处是关闭播放页会回到歌单，而不是一路退回首页。
    @State private var showsNowPlaying = false

    /// 曲目统一从 `PlaylistStore` 取：远程拉到了就用网易云的 30 首，否则退回本地选曲。
    ///
    /// 之前这里直接返回 `MusicLibrary.songs` —— 歌单的 `songIDs` 完全没被用上，
    /// 点进任何歌单都是整库 8 首。
    private var songs: [Song] { playlists.songs(for: playlist) }

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
        .fullScreenCover(isPresented: $showsNowPlaying) {
            NowPlayingView()
                .environment(player)
                .presentationBackground(.clear)
        }
        // 注意：**进页面不自动播放**，也不改变当前曲目。
        // 之前这里有个 -autoplay 的截图钩子会自动点第一行，
        // 导致一进歌单页第一首就被高亮/开始播 —— 已移除。
        // 自动化验证改由 -playlist N 只打开页面、不触发播放。
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

                Text("\(songs.count) 首 · \(totalDuration)")
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
                player.play(at: 0, in: songs)
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
                    // 按行号播，不做内容匹配 —— 点第几行就是第几行
                    player.play(at: index, in: songs)
                    showsNowPlaying = true
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
