import SwiftUI

// MARK: - 封面

struct ArtworkView: View {
    let name: String
    var cornerRadius: CGFloat = LiquidTheme.Radius.tile
    var showsStroke: Bool = true

    var body: some View {
        // 图片挂在 Color 的 overlay 上：Color 决定布局尺寸，图片溢出部分被裁掉。
        // 直接对 Image 用 scaledToFill 会让布局宽度按短边撑开，撑爆父容器。
        Color.clear
            .overlay {
                if let image = UIImage(named: name) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    // 资源缺失（网络电台等）不能让画面空着
                    FallbackArtwork(seed: name)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                if showsStroke {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
                }
            }
    }
}

/// 没有封面资源时的兜底：用名字做种子生成**稳定**的渐变 + 符号。
///
/// 注意不能用 `hashValue` —— Swift 每次启动都会随机化哈希种子，
/// 同一首歌的封面会每次打开都换个颜色。这里用字符码求和，结果稳定。
struct FallbackArtwork: View {
    let seed: String

    /// FNV-1a。不能用 `hashValue`（每次启动随机化），
    /// 也不能简单把字符码求和 —— 分布太窄，"netease_2632426028" 和 "netease_1862565773"
    /// 算出来只差 4%，二十条结果会全是同一个紫色。
    private var hue: Double {
        var hash: UInt32 = 2_166_136_261
        for byte in seed.utf8 {
            hash = (hash ^ UInt32(byte)) &* 16_777_619
        }
        return Double(hash % 360) / 360
    }

    private var isRadio: Bool { seed.hasPrefix("radio_") }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hue: hue, saturation: 0.52, brightness: 0.88),
                    Color(hue: (hue + 0.10).truncatingRemainder(dividingBy: 1), saturation: 0.66, brightness: 0.54)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: isRadio ? "dot.radiowaves.left.and.right" : "music.note")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.white.opacity(0.62))
        }
    }
}

/// 歌单封面：渐变 + 符号。真实产品里编辑部歌单就是这样生成的，不需要额外图片资源。
struct PlaylistCover: View {
    let playlist: Playlist
    var cornerRadius: CGFloat = LiquidTheme.Radius.tile
    var symbolSize: CGFloat = 26

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: playlist.colors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Image(systemName: playlist.symbol)
                    .font(.system(size: symbolSize, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
            }
    }
}

// MARK: - 玻璃控件

/// 玻璃图标按钮。44pt 触控区，圆形玻璃底，按下由系统玻璃自己给反馈。
struct GlassIconButton: View {
    let systemName: String
    var size: CGFloat = LiquidTheme.Hit.control
    var iconSize: CGFloat = 17
    var tint: Color = LiquidTheme.Palette.label
    var isActive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(isActive ? LiquidTheme.Palette.accent : tint)
                .frame(width: size, height: size)
                .liquidGlass(cornerRadius: size / 2, interactive: true)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(systemName))
    }
}

/// 筛选片。选中态 = 实心强调色，未选中 = 玻璃。
/// 玻璃只用于未选中态，避免"玻璃里再嵌玻璃"。
struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(LiquidTheme.Typography.button)
                .foregroundStyle(isSelected ? LiquidTheme.Palette.onAccent : LiquidTheme.Palette.label)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background {
                    if isSelected {
                        Capsule().fill(LiquidTheme.Palette.accent)
                    }
                }
                .liquidGlassCapsule(interactive: !isSelected)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 区块标题

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(LiquidTheme.Typography.section)
                    .foregroundStyle(LiquidTheme.Palette.label)

                if let subtitle {
                    Text(subtitle)
                        .font(LiquidTheme.Typography.caption)
                        .foregroundStyle(LiquidTheme.Palette.secondary)
                }
            }

            Spacer(minLength: LiquidTheme.Spacing.xs)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(LiquidTheme.Typography.button)
                    .foregroundStyle(LiquidTheme.Palette.accent)
                    .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - 歌曲行

/// 实底列表行。整行可点，高度 ≥ 60pt，右侧留出 44pt 的更多操作区。
struct SongRow: View {
    let song: Song
    var index: Int? = nil
    var isCurrent: Bool = false
    var isPlaying: Bool = false
    var isLiked: Bool = false
    var showsArtwork: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: LiquidTheme.Spacing.sm) {
                if let index {
                    Text("\(index)")
                        .font(LiquidTheme.Typography.numeric)
                        .foregroundStyle(
                            isCurrent ? LiquidTheme.Palette.accent : LiquidTheme.Palette.tertiary
                        )
                        .frame(width: 22, alignment: .center)
                        .monospacedDigit()
                }

                if showsArtwork {
                    ArtworkView(name: song.artworkName, cornerRadius: 10)
                        .frame(width: 48, height: 48)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                        .font(LiquidTheme.Typography.rowTitle)
                        .foregroundStyle(
                            isCurrent ? LiquidTheme.Palette.accent : LiquidTheme.Palette.label
                        )
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Text(song.artist)
                        Text("·")
                        Text(song.durationText)
                    }
                    .font(LiquidTheme.Typography.rowMeta)
                    .foregroundStyle(LiquidTheme.Palette.secondary)
                    .lineLimit(1)
                }

                Spacer(minLength: LiquidTheme.Spacing.xxs)

                if isCurrent && isPlaying {
                    PlayingIndicator()
                } else if isLiked {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(LiquidTheme.Palette.like)
                }
            }
            .frame(minHeight: LiquidTheme.Hit.row)
            .padding(.horizontal, LiquidTheme.Spacing.md)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 播放中的跳动条
struct PlayingIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = 0

    var body: some View {
        HStack(alignment: .bottom, spacing: 2.5) {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(LiquidTheme.Palette.accent)
                    .frame(width: 3, height: height(for: index))
            }
        }
        .frame(width: 16, height: 16, alignment: .bottom)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.62).repeatForever(autoreverses: true)) {
                phase = 1
            }
        }
    }

    private func height(for index: Int) -> CGFloat {
        let base: [CGFloat] = [6, 14, 9]
        return reduceMotion ? base[index] * 0.8 : base[index] * (0.5 + 0.5 * phase)
    }
}

/// 头部胶囊里的图标按钮 —— **不带自己的玻璃底**。
/// 胶囊已经是一层玻璃，再套一层就是"玻璃叠玻璃"，边界会糊成一片。
struct HeaderIconButton: View {
    let systemName: String
    var isActive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isActive ? LiquidTheme.Palette.accent : LiquidTheme.Palette.label)
                .frame(width: 40, height: 40)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 悬浮头部

/// 悬浮玻璃头部。
///
/// **胶囊贴合内容宽度**，静止时就是右上角一枚只装操作按钮的小胶囊 ——
/// 不会出现"一整条空胶囊"这种一眼就是 bug 的形态。
/// 滚动后屏幕标题从左侧淡入，胶囊随之向左生长，这就是"层级随滚动变化"。
struct ScreenHeader<Trailing: View>: View {
    let title: String
    let scrollOffset: CGFloat
    var showsBack: Bool = false
    var onBack: (() -> Void)? = nil
    @ViewBuilder var trailing: () -> Trailing

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 滚动超过 10pt 就展开。阈值不能大 —— 大标题一开始上移，
    /// 行内标题就该跟着出现，这才是 iOS 的行为。
    private var showsTitle: Bool { scrollOffset > 10 }

    var body: some View {
        HStack(spacing: LiquidTheme.Spacing.xs) {
            if showsBack, let onBack {
                // 返回键单独一枚玻璃圆钮，和右侧胶囊并列、不重叠
                GlassIconButton(systemName: "chevron.left", action: onBack)
            }

            Spacer(minLength: 0)

            HStack(spacing: 0) {
                if showsTitle {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(LiquidTheme.Palette.label)
                        .lineLimit(1)
                        .padding(.leading, 12)
                        .padding(.trailing, 2)
                        .transition(.opacity)
                }

                trailing()
            }
            .padding(4)
            .liquidGlass(cornerRadius: LiquidTheme.Radius.dock, tint: LiquidTheme.Palette.chromeTint)
            .glassEdge(cornerRadius: LiquidTheme.Radius.dock)
        }
        .animation(reduceMotion ? nil : LiquidTheme.Motion.snappy, value: showsTitle)
    }
}

// MARK: - 滚动偏移

private struct ScrollOffsetReader: ViewModifier {
    @Binding var offset: CGFloat

    func body(content: Content) -> some View {
        content.onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, newValue in
            offset = newValue
        }
    }
}

extension View {
    /// 把滚动距离读进 Binding，供悬浮头部做折叠联动。
    func readScrollOffset(into binding: Binding<CGFloat>) -> some View {
        modifier(ScrollOffsetReader(offset: binding))
    }
}

// MARK: - 进度条

/// 播放进度条。轨道 4pt、触控区 28pt —— 视觉细，手指按得到。
struct ProgressBar: View {
    @Binding var value: Double
    var tint: Color = LiquidTheme.Palette.onDark
    var onEditingChanged: (Bool) -> Void = { _ in }

    @State private var isDragging = false

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let knob: CGFloat = isDragging ? 14 : 10
            let offset = min(max(width * value, 0), width) - knob / 2

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(tint.opacity(0.22))
                    .frame(height: 4)

                Capsule()
                    .fill(tint.opacity(0.92))
                    .frame(width: max(0, width * value), height: 4)

                Circle()
                    .fill(tint)
                    .frame(width: knob, height: knob)
                    .shadow(color: .black.opacity(0.25), radius: 4, y: 1)
                    .offset(x: offset)
                    .opacity(isDragging ? 1 : 0.9)
            }
            .frame(height: 28)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if !isDragging {
                            isDragging = true
                            onEditingChanged(true)
                        }
                        value = min(max(gesture.location.x / width, 0), 1)
                    }
                    .onEnded { _ in
                        isDragging = false
                        onEditingChanged(false)
                    }
            )
            .animation(LiquidTheme.Motion.linear, value: isDragging)
        }
        .frame(height: 28)
    }
}

// MARK: - 迷你播放条

struct MiniPlayerBar: View {
    let song: Song
    let isPlaying: Bool
    let onTap: () -> Void
    let onPrevious: () -> Void
    let onPlayPause: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: LiquidTheme.Spacing.sm) {
            Button(action: onTap) {
                HStack(spacing: LiquidTheme.Spacing.sm) {
                    ArtworkView(name: song.artworkName, cornerRadius: 9)
                        .frame(width: 38, height: 38)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(song.title)
                            .font(LiquidTheme.Typography.rowTitle)
                            .foregroundStyle(LiquidTheme.Palette.label)
                            .lineLimit(1)
                        Text(song.artist)
                            .font(LiquidTheme.Typography.caption)
                            .foregroundStyle(LiquidTheme.Palette.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // 三个传输键放一个 spacing 0 的 HStack：每个按钮本身有 44pt 触控框、
            // 图标居中，视觉间距已经够了。分开排能给歌名多留 24pt。
            HStack(spacing: 0) {
                transportButton("backward.fill", size: 15, action: onPrevious)
                transportButton(isPlaying ? "pause.fill" : "play.fill", size: 17, action: onPlayPause)
                transportButton("forward.fill", size: 15, action: onNext)
            }
        }
        // 左右内边距要和胶囊圆角对齐：圆角 26、封面高 38、上边距 6，
        // 在那个高度上圆角已向内收 9.4pt，所以 leading 取 14 才不切角。
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.vertical, 6)
        // 实底：保证背后文字不透上来。玻璃只叠在上面做光泽和边缘。
        .background(
            RoundedRectangle(cornerRadius: LiquidTheme.Radius.dock, style: .continuous)
                .fill(LiquidTheme.Palette.controlFill)
        )
        .liquidGlass(
            cornerRadius: LiquidTheme.Radius.dock,
            // 控制栏要能读清歌名 —— 走 frosted（regular）+ 染色，
            // Tab Bar 则保持 clear，两者刻意不同。
            tint: LiquidTheme.Palette.controlTint
        )
        // 压在白色列表卡片上时，靠投影把它"抬"起来，否则同色会连成一整块
        .shadow(color: .black.opacity(0.09), radius: 16, y: 5)
        .glassEdge(cornerRadius: LiquidTheme.Radius.dock)
    }

    /// 玻璃条里的小控件用纯图标，不再叠一层玻璃
    private func transportButton(
        _ systemName: String,
        size: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(LiquidTheme.Palette.label)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 轻提示

/// 一闪而过的状态提示（"已经是第一首了"）。
///
/// 用实底 + 玻璃光泽，和内容面板同一套材质；
/// 加投影是为了让它从内容里"浮"出来 —— 提示必须一眼看到。
struct ToastPill: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(.subheadline).weight(.medium))
            .foregroundStyle(LiquidTheme.Palette.label)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Capsule().fill(LiquidTheme.Palette.controlFill))
            .liquidGlassCapsule()
            .glassEdgeCapsule()
            .shadow(color: .black.opacity(0.10), radius: 14, y: 4)
            .accessibilityElement()
            .accessibilityLabel(message)
    }
}

// MARK: - 悬浮 Tab Bar

struct LiquidTabBar: View {
    let items: [(icon: String, title: String)]
    @Binding var selection: Int

    @Namespace private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                let isSelected = index == selection

                Button {
                    guard !isSelected else { return }
                    withAnimation(reduceMotion ? nil : LiquidTheme.Motion.snappy) {
                        selection = index
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item.icon)
                            .font(.system(size: 18, weight: isSelected ? .semibold : .regular))
                            .frame(height: 22)

                        Text(item.title)
                            .font(.system(.caption2).weight(isSelected ? .semibold : .medium))
                    }
                    .foregroundStyle(
                        isSelected ? LiquidTheme.Palette.accent : LiquidTheme.Palette.secondary
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background {
                        // 选中态是一片**又亮又圆的玻璃块**，盖住图标和文字整块。
                        //
                        // 两轮踩坑：
                        // ① 纯白填充 invisible —— Tab Bar 被 chromeTint 加成接近白色，白叠白没有对比；
                        // ② 极淡靛蓝 #EEF0FF 在薰衣草底上勉强可见，但遇到**白色卡片**（我的/音乐库）
                        //    背后的玻璃也变白，又消失了。
                        //
                        // 结论：选中态不能只靠"更亮"，必须靠**色相**区分。
                        // 所以用 accent 染色 + 一层白色顶部高光保住玻璃感。
                        if isSelected {
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(LiquidTheme.Palette.accent.opacity(0.20))
                                .overlay {
                                    // 顶部高光：让染色块看起来是"玻璃"而不是"色块"
                                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                                        .fill(
                                            LinearGradient(
                                                colors: [.white.opacity(0.62), .white.opacity(0.04)],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                        )
                                }
                                .overlay {
                                    // 描边：顶部白色高光（玻璃感）+ 底部强调色（在白底上勾出形状）
                                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                                        .strokeBorder(
                                            LinearGradient(
                                                colors: [
                                                    .white.opacity(0.98),
                                                    LiquidTheme.Palette.accent.opacity(0.28)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 0.75
                                        )
                                }
                                .shadow(color: LiquidTheme.Palette.accent.opacity(0.22), radius: 8, y: 2)
                                .padding(.horizontal, 3)
                                .padding(.vertical, 1)
                                .matchedGeometryEffect(id: "tab-selection", in: namespace)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .padding(5)
        .liquidGlassCapsule(clear: true)
        .overlay {
            // 一道 1pt 的细亮线勾出整条栏的轮廓。
            // 之前用 0.5pt 纯白描边，压在白色玻璃上等于没画 ——
            // 现在底色是淡蓝紫，白线才立得住。
            Capsule().strokeBorder(
                LinearGradient(
                    colors: [.white.opacity(0.96), .white.opacity(0.42)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
        }
    }
}
