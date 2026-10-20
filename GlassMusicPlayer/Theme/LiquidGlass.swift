import SwiftUI
import UIKit

// MARK: - 液态玻璃

extension View {

    /// 液态玻璃。走 iOS 26 原生 `glassEffect`，材质的折射、镜面高光、
    /// 以及"背景越复杂越不透明"的自适应都由系统负责。
    ///
    /// **只用于 chrome 和内容面板**：导航栏 / 工具栏 / 浮层 / 小控件 / 卡片。
    /// 内容面板请用 `glassPanel()` —— 它已经把 `panelTint` 和细亮边配好了。
    ///
    /// - Parameters:
    ///   - cornerRadius: 同心圆角（内层 = 外层 − 内边距）
    ///   - interactive: 可点元素传 true，按下时玻璃会自己给出反馈
    ///   - tint: 复杂背景（如专辑封面）上压一点色，进一步提高不透明度
    ///   - clear: `Glass.clear` —— 几乎全透明，能清楚看见背后的画面。
    ///     适合压在图片/封面上（像 iOS 26 的 Dock）；压在白色卡片上会整块消失。
    func liquidGlass(
        cornerRadius: CGFloat = LiquidTheme.Radius.control,
        interactive: Bool = false,
        tint: Color? = nil,
        clear: Bool = false
    ) -> some View {
        var glass: Glass = clear ? .clear : .regular
        glass = glass.tint(tint)
        if interactive { glass = glass.interactive() }
        return glassEffect(glass, in: .rect(cornerRadius: cornerRadius))
    }

    /// 胶囊玻璃：Tab Bar、迷你播放条、筛选片
    func liquidGlassCapsule(
        interactive: Bool = false,
        tint: Color? = nil,
        clear: Bool = false
    ) -> some View {
        var glass: Glass = clear ? .clear : .regular
        glass = glass.tint(tint)
        if interactive { glass = glass.interactive() }
        return glassEffect(glass, in: .capsule)
    }
}

/// 把多个玻璃元素放进同一个容器，系统才能算出正确的融合关系。
/// 例如迷你播放条 + Tab Bar 叠在一起时，它们会像一滴水一样相互挤压，而不是硬邦邦地摞着。
struct LiquidGlassGroup<Content: View>: View {
    var spacing: CGFloat = 10
    @ViewBuilder var content: () -> Content

    var body: some View {
        GlassEffectContainer(spacing: spacing) {
            content()
        }
    }
}

// MARK: - 细亮边

extension View {
    /// 玻璃的"细亮边"：左上亮 → 右下暗的 0.5pt 描边。
    ///
    /// 系统材质自带的边缘在高对比背景上很清楚，但压在浅色卡片上时几乎看不见，
    /// 玻璃会退化成一块白板。补这一道能立刻把"这是一层玻璃"的边界读回来。
    func glassEdge(cornerRadius: CGFloat) -> some View {
        overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(glassEdgeGradient, lineWidth: 0.5)
        }
    }

    /// 胶囊版的细亮边
    func glassEdgeCapsule() -> some View {
        overlay {
            Capsule().strokeBorder(glassEdgeGradient, lineWidth: 0.5)
        }
    }

    private var glassEdgeGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.70),
                Color.white.opacity(0.06)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - 内容面板

/// 内容面板：浅玻璃底 + 细亮边。
///
/// 原本是实底（`solidCard`，白 + 0.5pt 描边）。用户要求改成"玻璃底框"后，
/// 试过纯 `glassEffect` + tint，但 **`Glass.regular` 的亮度随面积变化** ——
/// 同一份材质小胶囊是 ~232、大面板是 ~249，和上面的分段控件对不齐。
///
/// 所以改成"固定底色 + 玻璃光泽"：底色 `panelFill` 保证色调稳定，
/// 玻璃只负责表面的高光和边缘。
struct GlassPanel: ViewModifier {
    var cornerRadius: CGFloat = LiquidTheme.Radius.card

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(LiquidTheme.Palette.panelFill)
            )
            .liquidGlass(cornerRadius: cornerRadius)
            .glassEdge(cornerRadius: cornerRadius)
    }
}

extension View {
    func glassPanel(cornerRadius: CGFloat = LiquidTheme.Radius.card) -> some View {
        modifier(GlassPanel(cornerRadius: cornerRadius))
    }
}

// MARK: - 减弱动态效果

extension View {
    /// 尊重「减弱动态效果」：开启时不做动画，直接跳变。
    func motion<V: Equatable>(
        _ animation: Animation,
        reduceMotion: Bool,
        value: V
    ) -> some View {
        self.animation(reduceMotion ? nil : animation, value: value)
    }
}

// MARK: - 背景

/// 深色沉浸背景：专辑封面放大 + 重模糊 + 分层压暗。
/// 压暗是必须的 —— 封面再亮，白字也要有稳定的对比基准。
///
/// ⚠️ 封面必须挂在 `Color` 的 overlay 上再 `clipped()`。
/// 直接写 `Image().resizable().scaledToFill()` 会让图片按短边撑满，
/// 布局宽度被撑到屏幕之外，整个父容器跟着塌陷、所有子视图被顶出屏幕。
struct ArtworkBackdrop: View {
    let artworkName: String?

    var body: some View {
        Color.black
            .ignoresSafeArea()
            .overlay {
                if let artworkName {
                    Image(artworkName)
                        .resizable()
                        .scaledToFill()
                        .blur(radius: 70, opaque: true)
                }
            }
            .overlay {
                // 上浅下深：顶部留给状态栏，底部留给控制条
                LinearGradient(
                    colors: [
                        .black.opacity(0.30),
                        .black.opacity(0.44),
                        .black.opacity(0.72)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        // 注意：这里不能再加 .clipped()。
        // ignoresSafeArea 只扩展绘制区域、不改变布局尺寸，
        // 在它之后 clipped 会按安全区尺寸裁，屏幕底部会漏出一条下层内容。
    }
}

/// 稳定的内容背景：浅薰衣草底 + 四团柔光斑。
/// 不随滚动变化 —— 这是"内容区保持稳固背景，浮动导航和工具栏覆盖其上"的落点。
///
/// 为什么用 `RadialGradient` 而不是 `Circle().blur()`：两者视觉上一样柔和，
/// 但渐变是纯 GPU 绘制，静态背景不会持续付高斯模糊的开销。
struct SoftCanvas: View {
    var body: some View {
        ZStack {
            // 底色：浅薰衣草。比中性灰更有空气感，也衬得出玻璃的冷调。
            LinearGradient(
                colors: [
                    Color(hex: 0xF2F1FB),
                    Color(hex: 0xE8E7F7)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // 光斑压在左上/右上/左下/右下，中间留干净区域给正文
            orb(hex: 0x7C6BF0, alpha: 0.32, anchor: .topTrailing,   radius: 300)
            orb(hex: 0xA78BFA, alpha: 0.26, anchor: .topLeading,    radius: 340)
            orb(hex: 0x818CF8, alpha: 0.22, anchor: .bottomLeading, radius: 380)
            orb(hex: 0xC4B5FD, alpha: 0.20, anchor: .bottomTrailing, radius: 360)
        }
        .ignoresSafeArea()
    }

    private func orb(hex: UInt32, alpha: Double, anchor: UnitPoint, radius: CGFloat) -> some View {
        let color = Color(hex: hex)
        return RadialGradient(
            colors: [color.opacity(alpha), color.opacity(0)],
            center: anchor,
            startRadius: 10,
            endRadius: radius
        )
    }
}

/// 滚动内容的通用内边距：底部要给悬浮 Tab Bar + 迷你条让位
extension View {
    func screenPadding() -> some View {
        self
            .padding(.horizontal, LiquidTheme.Spacing.screenH)
            .padding(.bottom, LiquidTheme.Spacing.bottomSafe)
    }
}
