import SwiftUI

/// 搜索 —— 以浮层形式从首页升起。
/// 输入框是玻璃（它是 chrome），结果列表是实底卡片。
struct SearchView: View {
    /// 作为浮层弹出时为 true（显示「取消」并自动聚焦）；
    /// 作为 Tab 页常驻时为 false。
    var isModal: Bool = true

    @Environment(PlayerModel.self) private var player
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var query = ""
    @State private var scrollOffset: CGFloat = 0
    @FocusState private var isFocused: Bool

    private let recentSearches = ["午夜霓虹", "AURORA DRIFT", "合成器浪潮", "雨天", "NOVA"]

    private var results: [Song] {
        let keyword = query.trimmingCharacters(in: .whitespaces)
        guard !keyword.isEmpty else { return [] }
        return MusicLibrary.songs.filter {
            $0.title.localizedCaseInsensitiveContains(keyword)
            || $0.artist.localizedCaseInsensitiveContains(keyword)
            || $0.album.localizedCaseInsensitiveContains(keyword)
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            SoftCanvas()

            ScrollView {
                VStack(alignment: .leading, spacing: LiquidTheme.Spacing.lg) {
                    Color.clear.frame(height: 0)

                    if query.isEmpty {
                        recentSection
                        genreSection
                    } else if results.isEmpty {
                        emptyState
                    } else {
                        resultSection
                    }
                }
                .padding(.top, 76)
                .padding(.bottom, LiquidTheme.Spacing.xl)
            }
            .scrollIndicators(.hidden)
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            .readScrollOffset(into: $scrollOffset)
            .scrollDismissesKeyboard(.interactively)

            searchBar
        }
        .onAppear {
            if isModal { isFocused = true }
        }
    }

    // MARK: - 搜索栏

    private var searchBar: some View {
        HStack(spacing: LiquidTheme.Spacing.xs) {
            HStack(spacing: LiquidTheme.Spacing.xs) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(LiquidTheme.Palette.secondary)

                TextField("歌曲、艺人、专辑", text: $query)
                    .font(LiquidTheme.Typography.rowTitle)
                    .foregroundStyle(LiquidTheme.Palette.label)
                    .focused($isFocused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(LiquidTheme.Palette.tertiary)
                            .frame(width: 28, height: 28)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: LiquidTheme.Hit.control)
            .liquidGlassCapsule()

            if isModal {
                Button("取消") {
                    dismiss()
                }
                .font(LiquidTheme.Typography.button)
                .foregroundStyle(LiquidTheme.Palette.accent)
                .frame(minWidth: LiquidTheme.Hit.minimum, minHeight: LiquidTheme.Hit.minimum)
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, LiquidTheme.Spacing.md)
        .padding(.top, 8)
    }

    // MARK: - 最近搜索

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: LiquidTheme.Spacing.sm) {
            SectionHeader(title: "最近搜索", actionTitle: "清除") {}
                .padding(.horizontal, LiquidTheme.Spacing.screenH)

            FlowLayout(spacing: LiquidTheme.Spacing.xs) {
                ForEach(recentSearches, id: \.self) { keyword in
                    FilterChip(title: keyword, isSelected: false) {
                        query = keyword
                    }
                }
            }
            .padding(.horizontal, LiquidTheme.Spacing.screenH)
        }
    }

    // MARK: - 浏览分类

    private var genreSection: some View {
        VStack(alignment: .leading, spacing: LiquidTheme.Spacing.sm) {
            SectionHeader(title: "浏览分类")
                .padding(.horizontal, LiquidTheme.Spacing.screenH)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: LiquidTheme.Spacing.sm),
                    GridItem(.flexible(), spacing: LiquidTheme.Spacing.sm)
                ],
                spacing: LiquidTheme.Spacing.sm
            ) {
                ForEach(Self.genres, id: \.title) { genre in
                    Button {
                        query = genre.title
                    } label: {
                        HStack {
                            Text(genre.title)
                                .font(LiquidTheme.Typography.cardTitle)
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Image(systemName: genre.symbol)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 74)
                        .background(
                            LinearGradient(
                                colors: genre.colors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(cornerRadius: LiquidTheme.Radius.tile, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, LiquidTheme.Spacing.screenH)
        }
    }

    private static let genres: [(title: String, colors: [Color], symbol: String)] = [
        ("合成器浪潮", [Color(hex: 0x6C5CE7), Color(hex: 0xA855F7)], "waveform"),
        ("国风电音", [Color(hex: 0x2D3436), Color(hex: 0x636E72)], "leaf.fill"),
        ("Lo-Fi", [Color(hex: 0x0F766E), Color(hex: 0x38BDF8)], "moon.stars.fill"),
        ("电子", [Color(hex: 0xD63031), Color(hex: 0xFD79A8)], "bolt.fill"),
        ("氛围", [Color(hex: 0x4B6584), Color(hex: 0x778CA3)], "cloud.fill"),
        ("华语流行", [Color(hex: 0xE17055), Color(hex: 0xFDCB6E)], "music.mic")
    ]

    // MARK: - 结果

    private var resultSection: some View {
        VStack(alignment: .leading, spacing: LiquidTheme.Spacing.sm) {
            SectionHeader(title: "\(results.count) 个结果", subtitle: "匹配「\(query)」")
                .padding(.horizontal, LiquidTheme.Spacing.screenH)

            VStack(spacing: 0) {
                ForEach(Array(results.enumerated()), id: \.element.id) { index, song in
                    if index > 0 { hairline }

                    SongRow(
                        song: song,
                        isCurrent: song.id == player.current.id,
                        isPlaying: player.isPlaying,
                        isLiked: player.isLiked(song)
                    ) {
                        player.play(song, in: results)
                    }
                }
            }
            .glassPanel()
            .padding(.horizontal, LiquidTheme.Spacing.screenH)
        }
    }

    private var emptyState: some View {
        VStack(spacing: LiquidTheme.Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(LiquidTheme.Palette.tertiary)

            Text("没有找到「\(query)」")
                .font(LiquidTheme.Typography.rowTitle)
                .foregroundStyle(LiquidTheme.Palette.label)

            Text("换个关键词试试，或者从分类里找")
                .font(LiquidTheme.Typography.caption)
                .foregroundStyle(LiquidTheme.Palette.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private var hairline: some View {
        Rectangle()
            .fill(LiquidTheme.Palette.separator.opacity(0.5))
            .frame(height: 0.5)
            .padding(.leading, 76)
    }
}

// MARK: - 简易流式布局（搜索关键词 chip）

/// 关键词标签需要自动换行，SwiftUI 没有内置 FlowLayout，这里用 Layout 协议实现一个。
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rows: [CGFloat] = [0]
        var x: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                rows.append(0)
                x = 0
            }
            rows[rows.count - 1] = max(rows[rows.count - 1], size.height)
            x += size.width + spacing
        }

        let height = rows.reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(size)
            )
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

#Preview {
    SearchView()
        .environment(PlayerModel())
}
