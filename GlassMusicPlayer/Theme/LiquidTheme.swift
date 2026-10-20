import SwiftUI
import UIKit

/// BhandsMusic · 液态玻璃设计令牌。
///
/// 五条硬规则，对应设计约束：
///
/// 1. **玻璃只给 chrome** —— 导航栏 / 工具栏 / 浮层 / 小控件用玻璃；
///    正文卡片一律实底。这是"避免玻璃叠玻璃"最有效的一刀。
/// 2. **不叠玻璃** —— 两块玻璃之间必须有内容或留白，绝不直接摞在一起。
/// 3. **对比优先** —— 正文永远用 `label` 级对比度，不靠材质"透"出来的背景撑可读性。
/// 4. **同心圆角** —— 内层圆角 = 外层圆角 − 内边距，嵌套才不显脏。
/// 5. **动效可关** —— 所有滚动联动都读 `accessibilityReduceMotion`，关掉后直接跳变不做过渡。
///
/// 颜色全部走系统语义色，深浅色自动适配；字号全部走 `Font.TextStyle`，动态字体自动适配。
enum LiquidTheme {

    // MARK: - 调色板

    enum Palette {
        /// 页面底（分组列表底）
        static let canvas      = Color(uiColor: .systemGroupedBackground)
        /// 页面底（纯色底，用于以内容为主的页面）
        static let canvasPlain = Color(uiColor: .systemBackground)
        /// 实底卡片 —— 正文唯一的承载体
        static let card        = Color(uiColor: .secondarySystemGroupedBackground)
        /// 卡片内的次级块（封面占位、图标底）
        static let cardInset   = Color(uiColor: .tertiarySystemGroupedBackground)
        /// 卡片极细描边。替代阴影：液态玻璃靠"边"分层，不靠"影"。
        static let cardStroke  = Color(uiColor: .separator).opacity(0.55)

        static let label       = Color(uiColor: .label)
        static let secondary   = Color(uiColor: .secondaryLabel)
        static let tertiary    = Color(uiColor: .tertiaryLabel)
        static let quaternary  = Color(uiColor: .quaternaryLabel)
        static let separator   = Color(uiColor: .separator)

        /// 强调色：只用于可交互元素与选中态
        static let accent      = Color.indigo
        static let onAccent    = Color.white

        /// 深色沉浸页（正在播放）上的文字
        static let onDark      = Color.white
        static let onDarkSoft  = Color.white.opacity(0.70)

        /// 喜欢 / 收藏
        static let like        = Color(uiColor: .systemPink)

        /// 浮在内容之上的 chrome 加一点极淡的底色。
        ///
        /// 注意：`Glass.tint` 是给玻璃**着色**的，不是不透明度旋钮。
        /// 0.62 白色 → 玻璃变成白板，背后没东西可透，玻璃感全失；
        /// 0.26 → 玻璃很透，但灰色标签压在彩色卡片上对比不够。
        /// 0.42 是两者的平衡点：仍能看见背后的色块，文字也立得住。
        static let chromeTint  = Color(uiColor: .systemBackground).opacity(0.42)

        /// 迷你播放条（控制栏）专用。
        ///
        /// ⚠️ `Glass.tint` **不是不透明度旋钮** —— 调到 0.95 背后的文字照样透上来。
        /// 要做到"不透文字"只能垫一层实底（`controlFill`），玻璃只负责表面的光泽和边缘。
        /// 底色带一点蓝紫，才不会和白色 `solidCard` 连成一整块。
        static let controlFill = Color(hex: 0xECEEFF)
        static let controlTint = Color(hex: 0xE3E7FF).opacity(0.45)

        /// 内容面板 / 分段控件共用的底色。
        ///
        /// 为什么用实底而不是纯靠染色：**`Glass.regular` 的亮度会随面积变化** ——
        /// 同一份材质，小胶囊渲染成 ~232，大面板渲染成 ~249，光靠 tint 永远对不齐。
        /// 定一个固定底色，再用玻璃叠光泽，两者才是同一种观感。
        static let panelFill   = Color(hex: 0xE9E7F6)

        /// 底部 dock（迷你播放条 + Tab Bar）共用染色：淡蓝紫。
        ///
        /// 不能和 `chromeTint` 共用白色 —— 白色玻璃会随背景自适应，
        /// 压在白色卡片上就变成纯白，边界和选中态一起消失。
        /// 给它一个固定色相，无论背后是什么，dock 都是"一层淡蓝紫玻璃"。
        ///
        /// 迷你条和 Tab Bar 必须同色：两块玻璃上下摞在一起，颜色不一致会像 bug。
        static let dockTint   = Color(hex: 0xD3D8FF).opacity(0.46)
    }

    // MARK: - 圆角（同心嵌套）

    enum Radius {
        /// 全屏浮层
        static let sheet: CGFloat = 28
        /// 大卡片
        static let card: CGFloat = 22
        /// 中卡片 / 封面
        static let tile: CGFloat = 16
        /// 小控件 / 图标按钮
        static let control: CGFloat = 14
        /// 迷你播放条 / Tab Bar 胶囊
        static let dock: CGFloat = 26
        /// 胶囊
        static let pill: CGFloat = 999
    }

    // MARK: - 间距

    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 22
        static let xl: CGFloat = 28
        /// 首页区块之间的纵向间距。比 `xl` 紧一档 —— 大标题和胶囊并成一行后，
        /// 28pt 的段间距会让页面显得松散。
        static let section: CGFloat = 20
        /// 屏幕左右安全边距
        static let screenH: CGFloat = 20
        /// 滚动内容底部给悬浮 chrome 留的空间
        /// = 迷你条 50 + 间距 6 + Tab Bar 64 + 底部留白 16 + 余量
        static let bottomSafe: CGFloat = 148
    }

    // MARK: - 字体（全部走 TextStyle，动态字体自动缩放）

    enum Typography {
        static let hero      = Font.system(.largeTitle).weight(.bold)
        static let screen    = Font.system(.title).weight(.bold)
        static let section   = Font.system(.title3).weight(.semibold)
        static let cardTitle = Font.system(.headline)
        static let rowTitle  = Font.system(.body).weight(.medium)
        static let rowMeta   = Font.system(.subheadline)
        static let caption   = Font.system(.caption)
        static let overline  = Font.system(.caption2).weight(.semibold)
        static let button    = Font.system(.subheadline).weight(.semibold)
        static let lyric     = Font.system(.title3).weight(.medium)
        static let lyricIdle = Font.system(.body)
        static let numeric   = Font.system(.footnote).monospacedDigit()
        static let tabLabel  = Font.system(.caption2).weight(.medium)
    }

    // MARK: - 动效

    enum Motion {
        /// 状态切换：选中、开关、展开
        static let snappy = Animation.spring(response: 0.34, dampingFraction: 0.86)
        /// 大块位移：页面、浮层
        static let gentle = Animation.spring(response: 0.50, dampingFraction: 0.90)
        /// 数值变化：进度、音量
        static let linear = Animation.easeInOut(duration: 0.28)
        /// 滚动联动的插值系数（越大越跟手）
        static let scrollFollow: CGFloat = 0.12
    }

    // MARK: - 触控

    enum Hit {
        /// 任何可点元素的最小边
        static let minimum: CGFloat = 44
        /// 标准玻璃按钮直径
        static let control: CGFloat = 44
        /// 列表行最小高度
        static let row: CGFloat = 60
    }

    // MARK: - 滚动联动

    /// 头部从"透明"到"玻璃实心"的滚动距离
    static let headerGlassRange: CGFloat = 44
    /// 大标题淡出、行内标题淡入的滚动区间
    static let headerTitleRange: CGFloat = 56
}
