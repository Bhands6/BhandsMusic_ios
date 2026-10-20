import SwiftUI

/// 现在就听 —— 内容区实底、chrome 玻璃。
///
/// 页面结构：稳固的柔和底 → 可滚动的内容（大标题 / 横向货架 / 实底列表）
/// → 悬浮玻璃头部覆盖其上。滚动时大标题滚走、头部标题淡入。
struct HomeView: View {
    @Environment(PlayerModel.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var scrollOffset: CGFloat = 0
    @State private var selectedPlaylist: Playlist?
    @State private var showsSearch = false

    var body: some View {
        ZStack(alignment: .top) {
            SoftCanvas()

            ScrollView {
                VStack(alignment: .leading, spacing: LiquidTheme.Spacing.section) {
                    greeting
                    recentlyPlayedSection
                    radioSection
                    madeForYouSection
                    newReleasesSection
                    topSongsSection
                }
                .padding(.top, 14)
                .padding(.bottom, LiquidTheme.Spacing.bottomSafe)
            }
            .scrollIndicators(.hidden)
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            .defaultScrollAnchor(DebugLaunch.flag("scrollBottom") ? .bottom : .top)
            .readScrollOffset(into: $scrollOffset)

            ScreenHeader(title: "现在就听", scrollOffset: scrollOffset) {
                HStack(spacing: 0) {
                    HeaderIconButton(systemName: "magnifyingglass") {
                        showsSearch = true
                    }
                    HeaderIconButton(systemName: "person.crop.circle") {}
                }
            }
            .padding(.horizontal, LiquidTheme.Spacing.md)
            .padding(.top, 4)
        }
        .sheet(item: $selectedPlaylist) { playlist in
            PlaylistDetailView(playlist: playlist)
                .presentationBackground(.clear)
        }
        .sheet(isPresented: $showsSearch) {
            SearchView()
                .presentationBackground(.clear)
        }
        .onAppear {
            // 截图用：-playlist N 直接打开第 N 个歌单（1 起）
            let index = DebugLaunch.playlistIndex
            if index > 0, index <= MusicLibrary.playlists.count {
                selectedPlaylist = MusicLibrary.playlists[index - 1]
            }
        }
    }

    // MARK: - 大标题

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("现在就听")
                .font(LiquidTheme.Typography.hero)
                .foregroundStyle(LiquidTheme.Palette.label)

            // 日期不再单独占一行 —— 一行 overline 会把大标题往下顶 18pt，
            // 顶部就显得空。并进副标题，信息不丢，版面收紧。
            Text("\(Self.dateText) · 为你挑选的 \(MusicLibrary.songs.count) 首单曲，共 \(totalHours) 小时")
                .font(LiquidTheme.Typography.rowMeta)
                .foregroundStyle(LiquidTheme.Palette.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, LiquidTheme.Spacing.screenH)
    }

    private var totalHours: Int {
        let seconds = MusicLibrary.songs.reduce(0) { $0 + $1.duration }
        return max(1, Int(seconds / 3600))
    }

    private static var dateText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M 月 d 日 EEEE"
        return formatter.string(from: Date())
    }

    // MARK: - 最近播放

    private var recentlyPlayedSection: some View {
        VStack(alignment: .leading, spacing: LiquidTheme.Spacing.sm) {
            SectionHeader(title: "最近播放", subtitle: "接着上次听到的地方")
                .padding(.horizontal, LiquidTheme.Spacing.screenH)

            ScrollView(.horizontal) {
                HStack(spacing: LiquidTheme.Spacing.sm) {
                    ForEach(MusicLibrary.recentlyPlayed) { song in
                        Button {
                            player.play(song)
                        } label: {
                            VStack(alignment: .leading, spacing: LiquidTheme.Spacing.xs) {
                                ArtworkView(name: song.artworkName, cornerRadius: LiquidTheme.Radius.tile)
                                    .frame(width: 130, height: 130)

                                VStack(alignment: .leading, spacing: 2) {
                                    // 和「为你推荐」保持同一档字号，两块货架才不会一大一小
                                    Text(song.title)
                                        .font(.system(.subheadline).weight(.medium))
                                        .foregroundStyle(LiquidTheme.Palette.label)
                                        .lineLimit(1)

                                    Text(song.artist)
                                        .font(LiquidTheme.Typography.caption)
                                        .foregroundStyle(LiquidTheme.Palette.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .frame(width: 130, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, LiquidTheme.Spacing.screenH)
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: - 为你推荐

    private var madeForYouSection: some View {
        VStack(alignment: .leading, spacing: LiquidTheme.Spacing.sm) {
            SectionHeader(title: "为你推荐", subtitle: "根据最近的收听生成", actionTitle: "全部") {}
                .padding(.horizontal, LiquidTheme.Spacing.screenH)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: LiquidTheme.Spacing.sm),
                    GridItem(.flexible(), spacing: LiquidTheme.Spacing.sm),
                    GridItem(.flexible(), spacing: LiquidTheme.Spacing.sm)
                ],
                spacing: LiquidTheme.Spacing.md
            ) {
                ForEach(MusicLibrary.madeForYou) { playlist in
                    Button {
                        selectedPlaylist = playlist
                    } label: {
                        playlistCard(playlist)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, LiquidTheme.Spacing.screenH)
        }
    }

    private func playlistCard(_ playlist: Playlist) -> some View {
        VStack(alignment: .leading, spacing: LiquidTheme.Spacing.xs) {
            PlaylistCover(playlist: playlist, cornerRadius: LiquidTheme.Radius.tile, symbolSize: 22)
                .aspectRatio(1, contentMode: .fit)

            VStack(alignment: .leading, spacing: 1) {
                Text(playlist.title)
                    .font(.system(.subheadline).weight(.medium))
                    .foregroundStyle(LiquidTheme.Palette.label)
                    .lineLimit(1)

                // 三列时卡片只有 ~113pt 宽，长副标题会被截断，只留数量
                Text("\(playlist.count) 首")
                    .font(LiquidTheme.Typography.caption)
                    .foregroundStyle(LiquidTheme.Palette.secondary)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
    }

    // MARK: - 网络电台

    private var radioSection: some View {
        VStack(alignment: .leading, spacing: LiquidTheme.Spacing.sm) {
            SectionHeader(title: "网络电台", subtitle: "直播流 · 打开即听")
                .padding(.horizontal, LiquidTheme.Spacing.screenH)

            ScrollView(.horizontal) {
                HStack(spacing: LiquidTheme.Spacing.sm) {
                    ForEach(RadioCatalog.stations) { station in
                        stationCard(station)
                    }
                }
                .padding(.horizontal, LiquidTheme.Spacing.screenH)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func stationCard(_ station: RadioStation) -> some View {
        let isCurrent = player.current.title == station.name

        return Button {
            // 点任意一台都按整个电台列表播，切歌即换台
            player.play(RadioCatalog.song(for: station), in: RadioCatalog.songs)
        } label: {
            VStack(alignment: .leading, spacing: LiquidTheme.Spacing.xs) {
                ZStack {
                    RoundedRectangle(cornerRadius: LiquidTheme.Radius.tile, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [station.color.opacity(0.92), station.color.opacity(0.42)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Image(systemName: isCurrent ? "waveform" : "dot.radiowaves.left.and.right")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.94))
                        .symbolEffect(.variableColor.iterative, isActive: isCurrent && player.isPlaying)
                }
                .frame(width: 128, height: 128)

                VStack(alignment: .leading, spacing: 1) {
                    Text(station.name)
                        .font(LiquidTheme.Typography.caption.weight(.medium))
                        .foregroundStyle(LiquidTheme.Palette.label)
                        .lineLimit(1)
                    Text("\(station.scene) · \(station.style)")
                        .font(LiquidTheme.Typography.caption)
                        .foregroundStyle(LiquidTheme.Palette.secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: 128, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 新发行

    private var newReleasesSection: some View {
        VStack(alignment: .leading, spacing: LiquidTheme.Spacing.sm) {
            SectionHeader(title: "新发行", subtitle: "本周上架")
                .padding(.horizontal, LiquidTheme.Spacing.screenH)

            ScrollView(.horizontal) {
                HStack(spacing: LiquidTheme.Spacing.sm) {
                    ForEach(MusicLibrary.newReleases) { album in
                        VStack(alignment: .leading, spacing: LiquidTheme.Spacing.xs) {
                            ArtworkView(name: album.artworkName, cornerRadius: LiquidTheme.Radius.tile)
                                .frame(width: 128, height: 128)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(album.title)
                                    .font(LiquidTheme.Typography.caption.weight(.medium))
                                    .foregroundStyle(LiquidTheme.Palette.label)
                                    .lineLimit(1)
                                Text("\(album.artist) · \(String(album.year))")
                                    .font(LiquidTheme.Typography.caption)
                                    .foregroundStyle(LiquidTheme.Palette.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .frame(width: 128, alignment: .leading)
                    }
                }
                .padding(.horizontal, LiquidTheme.Spacing.screenH)
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: - 热门单曲

    private var topSongsSection: some View {
        VStack(alignment: .leading, spacing: LiquidTheme.Spacing.sm) {
            SectionHeader(title: "热门单曲", subtitle: "这周播放最多")
                .padding(.horizontal, LiquidTheme.Spacing.screenH)

            VStack(spacing: 0) {
                ForEach(Array(MusicLibrary.topSongs.prefix(5).enumerated()), id: \.element.id) { index, song in
                    if index > 0 {
                        hairline
                    }

                    SongRow(
                        song: song,
                        index: index + 1,
                        isCurrent: song.id == player.current.id,
                        isPlaying: player.isPlaying,
                        isLiked: player.isLiked(song)
                    ) {
                        player.play(song, in: MusicLibrary.topSongs)
                    }
                }
            }
            .glassPanel()
            .padding(.horizontal, LiquidTheme.Spacing.screenH)
        }
    }

    private var hairline: some View {
        Rectangle()
            .fill(LiquidTheme.Palette.separator.opacity(0.5))
            .frame(height: 0.5)
            .padding(.leading, 78)
    }
}

#Preview {
    HomeView()
        .environment(PlayerModel())
}
