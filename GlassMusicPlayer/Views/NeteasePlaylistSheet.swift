import SwiftUI

/// 网易云歌单详情。首页「我的歌单」点进来。
struct NeteasePlaylistSheet: View {
    let playlist: NeteasePlaylist

    @Environment(PlayerModel.self) private var player
    @Environment(\.dismiss) private var dismiss

    @State private var songs: [Song] = []
    @State private var isLoading = true
    @State private var errorText: String?
    @State private var showsNowPlaying = false

    var body: some View {
        ZStack(alignment: .top) {
            SoftCanvas()

            ScrollView {
                VStack(alignment: .leading, spacing: LiquidTheme.Spacing.lg) {
                    header
                    content
                }
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .presentationDetents([.large])
        .presentationBackground(.clear)
        .presentationDragIndicator(.visible)
        .task { await load() }
        .fullScreenCover(isPresented: $showsNowPlaying) {
            NowPlayingView()
                .environment(player)
                .presentationBackground(.clear)
        }
    }

    // MARK: - 头部

    private var header: some View {
        HStack(alignment: .top, spacing: LiquidTheme.Spacing.md) {
            AsyncImage(url: playlist.cover) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    FallbackArtwork(seed: playlist.name)
                }
            }
            .frame(width: 96, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(playlist.name)
                    .font(LiquidTheme.Typography.section)
                    .foregroundStyle(LiquidTheme.Palette.label)
                    .lineLimit(3)

                Text("\(playlist.trackCount) 首 · \(playlist.creator)")
                    .font(LiquidTheme.Typography.rowMeta)
                    .foregroundStyle(LiquidTheme.Palette.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LiquidTheme.Palette.label)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(LiquidTheme.Palette.panelFill))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("关闭"))
        }
        .padding(.horizontal, LiquidTheme.Spacing.screenH)
    }

    // MARK: - 内容

    @ViewBuilder
    private var content: some View {
        if isLoading {
            HStack(spacing: LiquidTheme.Spacing.xs) {
                ProgressView().controlSize(.small)
                Text("正在载入曲目…")
                    .font(LiquidTheme.Typography.caption)
                    .foregroundStyle(LiquidTheme.Palette.secondary)
            }
            .padding(.horizontal, LiquidTheme.Spacing.screenH)
        } else if let errorText {
            Text(errorText)
                .font(LiquidTheme.Typography.caption)
                .foregroundStyle(Color(hex: 0xD63031))
                .padding(.horizontal, LiquidTheme.Spacing.screenH)
        } else {
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
                        player.play(at: index, in: songs)
                        showsNowPlaying = true
                    }
                }
            }
            .glassPanel()
            .padding(.horizontal, LiquidTheme.Spacing.screenH)
        }
    }

    private func load() async {
        guard songs.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            // 歌单可能上千首，这里先取前 100 —— 够用且不会让请求太慢
            let tracks = try await NeteaseAPI.playlistTracks(id: playlist.id, limit: 100)
            songs = tracks.map(\.song)
            if songs.isEmpty { errorText = "这个歌单里没有可播放的曲目" }
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? "载入失败"
        }
    }
}
