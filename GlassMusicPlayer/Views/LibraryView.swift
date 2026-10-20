import SwiftUI

/// 音乐库 —— 三种视图（歌曲 / 专辑 / 艺人）共用同一个稳固底和同一个悬浮头部。
struct LibraryView: View {
    @Environment(PlayerModel.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var scrollOffset: CGFloat = 0
    @State private var segment = 0
    @State private var sortDescending = true

    private let segments = ["歌曲", "专辑", "艺人"]

    private var sortedSongs: [Song] {
        MusicLibrary.songs.sorted {
            sortDescending ? $0.plays > $1.plays : $0.title < $1.title
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            SoftCanvas()

            ScrollView {
                VStack(alignment: .leading, spacing: LiquidTheme.Spacing.md) {
                    titleBlock
                    segmentedControl
                    content
                }
                .padding(.top, 14)
                .padding(.bottom, LiquidTheme.Spacing.bottomSafe)
            }
            .scrollIndicators(.hidden)
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            .readScrollOffset(into: $scrollOffset)

            ScreenHeader(title: "音乐库", scrollOffset: scrollOffset) {
                HeaderIconButton(
                    systemName: sortDescending ? "arrow.down" : "arrow.up",
                    isActive: sortDescending
                ) {
                    withAnimation(reduceMotion ? nil : LiquidTheme.Motion.snappy) {
                        sortDescending.toggle()
                    }
                }
            }
            .padding(.horizontal, LiquidTheme.Spacing.md)
            .padding(.top, 4)
        }
    }

    // MARK: - 标题

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("音乐库")
                .font(LiquidTheme.Typography.hero)
                .foregroundStyle(LiquidTheme.Palette.label)

            Text("\(MusicLibrary.songs.count) 首歌曲 · \(MusicLibrary.albums.count) 张专辑 · \(MusicLibrary.artists.count) 位艺人")
                .font(LiquidTheme.Typography.rowMeta)
                .foregroundStyle(LiquidTheme.Palette.secondary)
        }
        .padding(.horizontal, LiquidTheme.Spacing.screenH)
    }

    // MARK: - 分段控件

    private var segmentedControl: some View {
        HStack(spacing: 0) {
            ForEach(Array(segments.enumerated()), id: \.offset) { index, title in
                let isSelected = index == segment

                Button {
                    withAnimation(reduceMotion ? nil : LiquidTheme.Motion.snappy) {
                        segment = index
                    }
                } label: {
                    Text(title)
                        .font(LiquidTheme.Typography.button)
                        .foregroundStyle(
                            isSelected ? LiquidTheme.Palette.onAccent : LiquidTheme.Palette.label
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background {
                            if isSelected {
                                Capsule().fill(LiquidTheme.Palette.accent)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .padding(4)
        // 和列表面板完全同色同边。这里**不叠 glassEffect** ——
        // 小面积玻璃会把底色压暗约 25 级（233→208），大面板却不会，
        // 两者放一起必然对不齐。纯底色 + 细亮边反而和面板一模一样。
        .background(Capsule().fill(LiquidTheme.Palette.panelFill))
        .glassEdgeCapsule()
        .padding(.horizontal, LiquidTheme.Spacing.screenH)
    }

    // MARK: - 内容

    @ViewBuilder
    private var content: some View {
        switch segment {
        case 0: songList
        case 1: albumGrid
        default: artistList
        }
    }

    private var songList: some View {
        VStack(spacing: 0) {
            ForEach(Array(sortedSongs.enumerated()), id: \.element.id) { index, song in
                if index > 0 { hairline(leading: 78) }

                SongRow(
                    song: song,
                    index: index + 1,
                    isCurrent: song.id == player.current.id,
                    isPlaying: player.isPlaying,
                    isLiked: player.isLiked(song)
                ) {
                    player.play(song, in: sortedSongs)
                }
            }
        }
        .glassPanel()
        .padding(.horizontal, LiquidTheme.Spacing.screenH)
    }

    private var albumGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: LiquidTheme.Spacing.sm),
                GridItem(.flexible(), spacing: LiquidTheme.Spacing.sm)
            ],
            spacing: LiquidTheme.Spacing.lg
        ) {
            ForEach(MusicLibrary.albums) { album in
                Button {
                    if let song = MusicLibrary.songs.first(where: { $0.album == album.title }) {
                        player.play(song)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: LiquidTheme.Spacing.xs) {
                        ArtworkView(name: album.artworkName, cornerRadius: LiquidTheme.Radius.tile)
                            .aspectRatio(1, contentMode: .fit)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(album.title)
                                .font(LiquidTheme.Typography.cardTitle)
                                .foregroundStyle(LiquidTheme.Palette.label)
                                .lineLimit(1)
                            Text("\(album.artist) · \(String(album.year))")
                                .font(LiquidTheme.Typography.caption)
                                .foregroundStyle(LiquidTheme.Palette.secondary)
                                .lineLimit(1)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, LiquidTheme.Spacing.screenH)
    }

    private var artistList: some View {
        VStack(spacing: 0) {
            ForEach(Array(MusicLibrary.artists.enumerated()), id: \.element.id) { index, artist in
                if index > 0 { hairline(leading: 78) }

                Button {
                    if let song = MusicLibrary.songs.first(where: { $0.artist == artist.name }) {
                        player.play(song)
                    }
                } label: {
                    HStack(spacing: LiquidTheme.Spacing.sm) {
                        ArtworkView(name: artist.artworkName, cornerRadius: 26)
                            .frame(width: 52, height: 52)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(artist.name)
                                .font(LiquidTheme.Typography.rowTitle)
                                .foregroundStyle(LiquidTheme.Palette.label)
                                .lineLimit(1)
                            Text("\(artist.genre) · \(artist.listenersText)")
                                .font(LiquidTheme.Typography.rowMeta)
                                .foregroundStyle(LiquidTheme.Palette.secondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 0)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(LiquidTheme.Palette.tertiary)
                    }
                    .frame(minHeight: LiquidTheme.Hit.row)
                    .padding(.horizontal, LiquidTheme.Spacing.md)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .glassPanel()
        .padding(.horizontal, LiquidTheme.Spacing.screenH)
    }

    private func hairline(leading: CGFloat) -> some View {
        Rectangle()
            .fill(LiquidTheme.Palette.separator.opacity(0.5))
            .frame(height: 0.5)
            .padding(.leading, leading)
    }
}

#Preview {
    LibraryView()
        .environment(PlayerModel())
}
