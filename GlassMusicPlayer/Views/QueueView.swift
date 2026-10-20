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

            ScrollView {
                VStack(alignment: .leading, spacing: LiquidTheme.Spacing.lg) {
                    nowPlayingSection
                    upNextSection
                }
                .padding(.top, 72)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)

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

    private var upNextSection: some View {
        VStack(alignment: .leading, spacing: LiquidTheme.Spacing.sm) {
            sectionTitle("接下来播放")

            VStack(spacing: 0) {
                ForEach(Array(player.upNext.enumerated()), id: \.element.id) { index, song in
                    if index > 0 {
                        Rectangle()
                            .fill(LiquidTheme.Palette.separator.opacity(0.5))
                            .frame(height: 0.5)
                            .padding(.leading, 68)
                    }

                    Button {
                        player.play(song, in: player.queue)
                    } label: {
                        HStack(spacing: LiquidTheme.Spacing.sm) {
                            ArtworkView(name: song.artworkName, cornerRadius: 10)
                                .frame(width: 44, height: 44)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(song.title)
                                    .font(LiquidTheme.Typography.rowTitle)
                                    .foregroundStyle(LiquidTheme.Palette.onDark)
                                    .lineLimit(1)
                                Text(song.artist)
                                    .font(LiquidTheme.Typography.rowMeta)
                                    .foregroundStyle(LiquidTheme.Palette.onDarkSoft)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 0)

                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(LiquidTheme.Palette.onDark.opacity(0.35))
                                .frame(width: 32, height: LiquidTheme.Hit.minimum)
                        }
                        .frame(minHeight: LiquidTheme.Hit.row)
                        .padding(.horizontal, LiquidTheme.Spacing.sm)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(
                LiquidTheme.Palette.card,
                in: RoundedRectangle(cornerRadius: LiquidTheme.Radius.tile, style: .continuous)
            )
            .padding(.horizontal, LiquidTheme.Spacing.screenH)
        }
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
