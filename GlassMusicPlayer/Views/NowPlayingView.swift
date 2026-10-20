import SwiftUI

/// 正在播放 —— 深色沉浸层。
///
/// 背景是重模糊的专辑封面（稳定不动），所有控件以玻璃浮在它上面。
/// 封面本身可点，切到歌词模式；两种模式共用同一套 chrome，切换是交叉淡入。
struct NowPlayingView: View {
    @Environment(PlayerModel.self) private var player
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isScrubbing = false
    @State private var showsQueue = DebugLaunch.flag("queue")

    private var song: Song { player.current }

    var body: some View {
        @Bindable var player = player

        ZStack {
            ArtworkBackdrop(artworkName: song.artworkName)

            VStack(spacing: 0) {
                topBar

                Spacer(minLength: LiquidTheme.Spacing.sm)

                stage

                Spacer(minLength: LiquidTheme.Spacing.sm)

                infoBlock

                if song.isLive {
                    // 直播流没有时长、不能拖进度，换成状态标签
                    liveBadge
                        .padding(.top, LiquidTheme.Spacing.md)
                } else {
                    // 拖拽时把写入转成 seek；同时标记 isSeeking，
                    // 否则播放器的进度回调会不停覆盖手指位置，滑块会"跳回去"
                    ProgressBar(
                        value: Binding(
                            get: { player.progress },
                            set: { player.seek(to: $0) }
                        )
                    ) { editing in
                        isScrubbing = editing
                        player.isSeeking = editing
                    }
                    .padding(.top, LiquidTheme.Spacing.md)

                    timeRow
                }

                transport
                    .padding(.top, LiquidTheme.Spacing.md)

                bottomBar
                    .padding(.top, LiquidTheme.Spacing.lg)
            }
            .padding(.horizontal, LiquidTheme.Spacing.lg)
            .padding(.bottom, LiquidTheme.Spacing.xs)
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showsQueue) {
            QueueView()
                .presentationBackground(.clear)
        }
    }

    // MARK: - 顶栏

    private var topBar: some View {
        HStack {
            GlassIconButton(systemName: "chevron.down", tint: LiquidTheme.Palette.onDark) {
                dismiss()
            }

            Spacer()

            Text("正在播放")
                .font(LiquidTheme.Typography.overline)
                .foregroundStyle(LiquidTheme.Palette.onDarkSoft)
                .textCase(.uppercase)

            Spacer()

            GlassIconButton(systemName: "ellipsis", tint: LiquidTheme.Palette.onDark) {}
        }
        .padding(.top, LiquidTheme.Spacing.xs)
    }

    // MARK: - 舞台（封面 / 歌词）

    private var stage: some View {
        ZStack {
            if player.showsLyrics {
                lyricsStage
                    .transition(.opacity)
            } else {
                artworkStage
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : LiquidTheme.Motion.gentle, value: player.showsLyrics)
    }

    private var artworkStage: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height, 340)

            ArtworkView(name: song.artworkName, cornerRadius: LiquidTheme.Radius.card)
                .frame(width: side, height: side)
                .shadow(color: .black.opacity(0.40), radius: 30, y: 18)
                .scaleEffect(player.isPlaying ? 1 : 0.94)
                .animation(reduceMotion ? nil : LiquidTheme.Motion.gentle, value: player.isPlaying)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(reduceMotion ? nil : LiquidTheme.Motion.gentle) {
                        player.showsLyrics = true
                    }
                }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(Text("显示歌词"))
        }
    }

    private var lyricsStage: some View {
        Group {
            if song.isInstrumental {
                VStack(spacing: LiquidTheme.Spacing.xs) {
                    Image(systemName: "music.note")
                        .font(.system(size: 30, weight: .light))
                    Text("纯音乐 · 暂无歌词")
                        .font(LiquidTheme.Typography.rowMeta)
                }
                .foregroundStyle(LiquidTheme.Palette.onDarkSoft)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                LyricsPane(song: song, progress: player.progress)
                    .onTapGesture {
                        withAnimation(reduceMotion ? nil : LiquidTheme.Motion.gentle) {
                            player.showsLyrics = false
                        }
                    }
            }
        }
    }

    // MARK: - 曲目信息

    private var infoBlock: some View {
        HStack(alignment: .center, spacing: LiquidTheme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 3) {
                Text(song.title)
                    .font(.system(.title2).weight(.bold))
                    .foregroundStyle(LiquidTheme.Palette.onDark)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text("\(song.artist) · \(song.album)")
                    .font(LiquidTheme.Typography.rowMeta)
                    .foregroundStyle(LiquidTheme.Palette.onDarkSoft)
                    .lineLimit(1)
            }

            Spacer(minLength: LiquidTheme.Spacing.xs)

            Button {
                player.toggleLike(song)
            } label: {
                Image(systemName: player.isLiked(song) ? "heart.fill" : "heart")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(
                        player.isLiked(song) ? LiquidTheme.Palette.like : LiquidTheme.Palette.onDarkSoft
                    )
                    .frame(width: LiquidTheme.Hit.minimum, height: LiquidTheme.Hit.minimum)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(player.isLiked(song) ? "取消喜欢" : "喜欢"))
        }
    }

    /// 直播流的状态标签，替代进度条
    private var liveBadge: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(LiquidTheme.Palette.like)
                .frame(width: 7, height: 7)
                .opacity(player.isPlaying ? 1 : 0.35)

            Text(player.isPlaying ? "直播中" : "已暂停")
                .font(LiquidTheme.Typography.caption.weight(.medium))
                .foregroundStyle(LiquidTheme.Palette.onDarkSoft)

            Spacer()

            Text("直播流不可拖动")
                .font(LiquidTheme.Typography.caption)
                .foregroundStyle(LiquidTheme.Palette.onDarkSoft.opacity(0.7))
        }
        .frame(height: 20)
        .accessibilityElement(children: .combine)
    }

    private var timeRow: some View {
        HStack {
            Text(Song.timeText(player.elapsed))
            Spacer()
            Text("-" + Song.timeText(player.remaining))
        }
        .font(LiquidTheme.Typography.numeric)
        .foregroundStyle(LiquidTheme.Palette.onDarkSoft)
        .padding(.top, 2)
    }

    // MARK: - 传输控制

    private var transport: some View {
        HStack(spacing: 0) {
            transportButton(
                "shuffle",
                size: 18,
                isActive: player.isShuffleOn
            ) {
                player.isShuffleOn.toggle()
            }

            transportButton("backward.fill", size: 26) {
                player.previous()
            }

            Button {
                player.togglePlayPause()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 27, weight: .semibold))
                    .foregroundStyle(LiquidTheme.Palette.onDark)
                    .frame(width: 74, height: 74)
                    .liquidGlass(
                        cornerRadius: 37,
                        interactive: true,
                        tint: Color.white.opacity(0.42)
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .accessibilityLabel(Text(player.isPlaying ? "暂停" : "播放"))

            transportButton("forward.fill", size: 26) {
                player.next()
            }

            transportButton(
                player.repeatMode.symbol,
                size: 18,
                isActive: player.repeatMode != .off
            ) {
                player.repeatMode = player.repeatMode.next
            }
        }
    }

    private func transportButton(
        _ systemName: String,
        size: CGFloat,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(
                    isActive ? LiquidTheme.Palette.onDark : LiquidTheme.Palette.onDarkSoft
                )
                .frame(width: 52, height: 52)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    // MARK: - 底部工具栏

    private var bottomBar: some View {
        HStack {
            GlassIconButton(
                systemName: "quote.bubble",
                tint: player.showsLyrics ? LiquidTheme.Palette.onDark : LiquidTheme.Palette.onDarkSoft,
                isActive: player.showsLyrics
            ) {
                withAnimation(reduceMotion ? nil : LiquidTheme.Motion.gentle) {
                    player.showsLyrics.toggle()
                }
            }

            Spacer()

            GlassIconButton(systemName: "list.bullet", tint: LiquidTheme.Palette.onDarkSoft) {
                showsQueue = true
            }

            Spacer()

            GlassIconButton(systemName: "airplayaudio", tint: LiquidTheme.Palette.onDarkSoft) {}
        }
    }
}

// MARK: - 歌词面板

/// 歌词独立成组件：它有自己的滚动定位逻辑，不该和播放器的其它部分耦合。
struct LyricsPane: View {
    let song: Song
    let progress: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var lines: [LyricLine] { song.lyrics }

    private var activeIndex: Int {
        let current = progress * song.duration
        var index = 0
        for (offset, line) in lines.enumerated() where line.time <= current {
            index = offset
        }
        return index
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 22) {
                    ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                        let isActive = index == activeIndex

                        Text(line.text)
                            .font(isActive ? LiquidTheme.Typography.lyric : LiquidTheme.Typography.lyricIdle)
                            .foregroundStyle(
                                isActive
                                ? LiquidTheme.Palette.onDark
                                : LiquidTheme.Palette.onDark.opacity(0.42)
                            )
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .id(line.id)
                            .animation(reduceMotion ? nil : LiquidTheme.Motion.linear, value: activeIndex)
                    }
                }
                .padding(.vertical, 130)
                .padding(.horizontal, LiquidTheme.Spacing.xs)
            }
            .scrollIndicators(.hidden)
            .defaultScrollAnchor(.center)
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.16),
                        .init(color: .black, location: 0.84),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .onAppear {
                proxy.scrollTo(lines[activeIndex].id, anchor: .center)
            }
            .onChange(of: activeIndex) { _, newValue in
                withAnimation(reduceMotion ? nil : LiquidTheme.Motion.linear) {
                    proxy.scrollTo(lines[newValue].id, anchor: .center)
                }
            }
        }
    }
}

#Preview {
    NowPlayingView()
        .environment(PlayerModel())
}
