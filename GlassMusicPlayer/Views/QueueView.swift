import SwiftUI

/// 播放队列 —— 从正在播放页以浮层升起。
///
/// 背景沿用封面的模糊氛围，与播放器保持连续；行本身是实底深色卡片，
/// 不在模糊图上直接铺文字。
struct QueueView: View {
    @Environment(PlayerModel.self) private var player
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            ArtworkBackdrop(artworkName: player.current.artworkName)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: LiquidTheme.Spacing.lg) {
                        nowPlayingSection
                        queueSection
                    }
                    .padding(.top, 72)
                    .padding(.bottom, 40)
                }
                // 能滚，但不显示滚动条 —— 队列页是全屏沉浸式，右侧一条灰线会破坏氛围。
                // 位置感交给标题旁的「5 / 20」。
                .scrollIndicators(.hidden)
                .onAppear {
                    // 进来就定位到正在播放那首，前后都能滚
                    proxy.scrollTo(player.current.id, anchor: .center)
                }
            }

            headerBar
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - 头部

    private var headerBar: some View {
        HStack {
            GlassIconButton(systemName: "chevron.down", tint: LiquidTheme.Palette.onDark) {
                dismiss()
            }

            Spacer()

            Text("播放队列")
                .font(LiquidTheme.Typography.overline)
                .foregroundStyle(LiquidTheme.Palette.onDarkSoft)
                .textCase(.uppercase)

            Spacer()

            GlassIconButton(systemName: "trash", tint: LiquidTheme.Palette.onDarkSoft) {}
        }
        .padding(.horizontal, LiquidTheme.Spacing.md)
        .padding(.top, LiquidTheme.Spacing.xs)
    }

    // MARK: - 正在播放

    private var nowPlayingSection: some View {
        VStack(alignment: .leading, spacing: LiquidTheme.Spacing.sm) {
            sectionTitle("正在播放")

            HStack(spacing: LiquidTheme.Spacing.sm) {
                ArtworkView(name: player.current.artworkName, cornerRadius: 12)
                    .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 3) {
                    Text(player.current.title)
                        .font(LiquidTheme.Typography.rowTitle)
                        .foregroundStyle(LiquidTheme.Palette.onDark)
                        .lineLimit(1)

                    Text("\(player.current.artist) · \(player.current.album)")
                        .font(LiquidTheme.Typography.rowMeta)
                        .foregroundStyle(LiquidTheme.Palette.onDarkSoft)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                PlayingIndicator()
            }
            .padding(LiquidTheme.Spacing.sm)
            .background(
                LiquidTheme.Palette.card,
                in: RoundedRectangle(cornerRadius: LiquidTheme.Radius.tile, style: .continuous)
            )
            .padding(.horizontal, LiquidTheme.Spacing.screenH)
        }
    }

    // MARK: - 接下来播放

    private var queueSection: some View {
        VStack(alignment: .leading, spacing: LiquidTheme.Spacing.sm) {
            HStack {
                sectionTitle("队列")
                Spacer()
                Text("\(player.currentIndex + 1) / \(player.queue.count)")
                    .font(LiquidTheme.Typography.rowMeta)
                    .foregroundStyle(LiquidTheme.Palette.onDarkSoft)
            }
            .padding(.trailing, LiquidTheme.Spacing.screenH)

            VStack(spacing: 0) {
                // 整条队列全列出来 —— 往上能看听过，往下能看还没播的。
                // 之前只给 `upNext`，听过的歌在界面上根本找不到。
                ForEach(Array(player.queue.enumerated()), id: \.element.id) { index, song in
                    if index > 0 {
                        Rectangle()
                            .fill(LiquidTheme.Palette.separator.opacity(0.5))
                            .frame(height: 0.5)
                            .padding(.leading, 68)
                    }

                    queueRow(song, index: index)
                }
            }
            .background(
                LiquidTheme.Palette.card,
                in: RoundedRectangle(cornerRadius: LiquidTheme.Radius.tile, style: .continuous)
            )
            .padding(.horizontal, LiquidTheme.Spacing.screenH)
        }
    }

    private func queueRow(_ song: Song, index: Int) -> some View {
        let isCurrent = song.id == player.current.id
        let isPlayed = index < player.currentIndex

        return Button {
            player.play(at: index, in: player.queue)
        } label: {
            HStack(spacing: LiquidTheme.Spacing.sm) {
                ArtworkView(name: song.artworkName, cornerRadius: 10)
                    .frame(width: 44, height: 44)
                    // 听过的封面压暗，一眼能分出前后
                    .opacity(isPlayed ? 0.45 : 1)

                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                        .font(LiquidTheme.Typography.rowTitle)
                        .foregroundStyle(
                            isCurrent ? LiquidTheme.Palette.accent
                                      : (isPlayed ? LiquidTheme.Palette.onDark.opacity(0.45)
                                                  : LiquidTheme.Palette.onDark)
                        )
                        .lineLimit(1)
                    Text(song.artist)
                        .font(LiquidTheme.Typography.rowMeta)
                        .foregroundStyle(LiquidTheme.Palette.onDarkSoft.opacity(isPlayed ? 0.6 : 1))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if isCurrent {
                    PlayingIndicator()
                }
            }
            .frame(minHeight: LiquidTheme.Hit.row)
            .padding(.horizontal, LiquidTheme.Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(song.id)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(LiquidTheme.Typography.section)
            .foregroundStyle(LiquidTheme.Palette.onDark)
            .padding(.horizontal, LiquidTheme.Spacing.screenH)
    }
}

#Preview {
    QueueView()
        .environment(PlayerModel())
}
