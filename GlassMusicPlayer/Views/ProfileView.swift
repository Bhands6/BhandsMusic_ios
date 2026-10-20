import SwiftUI

/// 我的 —— 账户与设置。整页只有悬浮头部是玻璃，其余全是实底分组卡片。
struct ProfileView: View {
    @Environment(PlayerModel.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var scrollOffset: CGFloat = 0
    @State private var equalizerOn = true
    @State private var sleepTimerOn = false
    @State private var losslessOnly = true

    var body: some View {
        ZStack(alignment: .top) {
            SoftCanvas()

            ScrollView {
                VStack(alignment: .leading, spacing: LiquidTheme.Spacing.lg) {
                    titleBlock
                    profileCard
                    statsCard
                    playbackSection
                    accountSection
                    footer
                }
                .padding(.top, 14)
                .padding(.bottom, LiquidTheme.Spacing.bottomSafe)
            }
            .scrollIndicators(.hidden)
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            .defaultScrollAnchor(DebugLaunch.flag("scrollBottom") ? .bottom : .top)
            .readScrollOffset(into: $scrollOffset)

            ScreenHeader(title: "我的", scrollOffset: scrollOffset) {
                HeaderIconButton(systemName: "gearshape") {}
            }
            .padding(.horizontal, LiquidTheme.Spacing.md)
            .padding(.top, 4)
        }
    }

    // MARK: - 标题

    private var titleBlock: some View {
        Text("我的")
            .font(LiquidTheme.Typography.hero)
            .foregroundStyle(LiquidTheme.Palette.label)
            .padding(.horizontal, LiquidTheme.Spacing.screenH)
    }

    // MARK: - 账户卡

    private var profileCard: some View {
        HStack(spacing: LiquidTheme.Spacing.md) {
            Image("avatar_rider")
                .resizable()
                .scaledToFill()
                .frame(width: 64, height: 64)
                .clipShape(Circle())
                .overlay {
                    Circle().strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5)
                }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("夜行者_K")
                        .font(LiquidTheme.Typography.section)
                        .foregroundStyle(LiquidTheme.Palette.label)

                    Text("会员")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(LiquidTheme.Palette.onAccent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(LiquidTheme.Palette.accent))
                }

                Text("BhandsMusic 会员 · 有效期至 2027-03-18")
                    .font(LiquidTheme.Typography.caption)
                    .foregroundStyle(LiquidTheme.Palette.secondary)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(LiquidTheme.Palette.tertiary)
        }
        .padding(LiquidTheme.Spacing.md)
        .glassPanel()
        .padding(.horizontal, LiquidTheme.Spacing.screenH)
    }

    // MARK: - 统计

    private var statsCard: some View {
        HStack(spacing: 0) {
            stat(value: "\(player.likedIDs.count + 126)", label: "收藏歌曲")
            divider
            stat(value: "\(MusicLibrary.playlists.count)", label: "我的歌单")
            divider
            stat(value: "36h", label: "本月收听")
        }
        .padding(.vertical, LiquidTheme.Spacing.md)
        .glassPanel()
        .padding(.horizontal, LiquidTheme.Spacing.screenH)
    }

    private func stat(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(LiquidTheme.Palette.label)
                .monospacedDigit()
            Text(label)
                .font(LiquidTheme.Typography.caption)
                .foregroundStyle(LiquidTheme.Palette.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle()
            .fill(LiquidTheme.Palette.separator.opacity(0.5))
            .frame(width: 0.5, height: 30)
    }

    // MARK: - 播放设置

    private var playbackSection: some View {
        VStack(alignment: .leading, spacing: LiquidTheme.Spacing.sm) {
            SectionHeader(title: "播放与音质")
                .padding(.horizontal, LiquidTheme.Spacing.screenH)

            VStack(spacing: 0) {
                navigationRow(
                    icon: "waveform.badge.magnifyingglass",
                    tint: LiquidTheme.Palette.accent,
                    title: "音质与下载",
                    value: losslessOnly ? "仅无损" : "自动"
                )

                rowDivider

                toggleRow(
                    icon: "slider.horizontal.3",
                    tint: Color(hex: 0x00B894),
                    title: "均衡器",
                    subtitle: "赛博低音",
                    isOn: $equalizerOn
                )

                rowDivider

                toggleRow(
                    icon: "moon.zzz.fill",
                    tint: Color(hex: 0x6C5CE7),
                    title: "睡眠定时",
                    subtitle: sleepTimerOn ? "30 分钟后停止" : "关闭",
                    isOn: $sleepTimerOn
                )
            }
            .glassPanel()
            .padding(.horizontal, LiquidTheme.Spacing.screenH)
        }
    }

    // MARK: - 账户

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: LiquidTheme.Spacing.sm) {
            SectionHeader(title: "账户")
                .padding(.horizontal, LiquidTheme.Spacing.screenH)

            VStack(spacing: 0) {
                navigationRow(
                    icon: "person.badge.key.fill",
                    tint: Color(hex: 0xE17055),
                    title: "账号与安全",
                    value: nil
                )

                rowDivider

                navigationRow(
                    icon: "arrow.down.circle.fill",
                    tint: Color(hex: 0x0984E3),
                    title: "已下载",
                    value: "12 首"
                )

                rowDivider

                navigationRow(
                    icon: "info.circle.fill",
                    tint: LiquidTheme.Palette.secondary,
                    title: "关于 BhandsMusic",
                    value: "v1.0.0"
                )
            }
            .glassPanel()
            .padding(.horizontal, LiquidTheme.Spacing.screenH)
        }
    }

    private var footer: some View {
        VStack(spacing: LiquidTheme.Spacing.xs) {
            Button {} label: {
                Text("退出登录")
                    .font(LiquidTheme.Typography.button)
                    .foregroundStyle(Color(hex: 0xD63031))
                    .frame(maxWidth: .infinity)
                    .frame(height: LiquidTheme.Hit.control)
                    .glassPanel(cornerRadius: LiquidTheme.Radius.tile)
            }
            .buttonStyle(.plain)

            Text("BhandsMusic · 构建于液态玻璃")
                .font(LiquidTheme.Typography.caption)
                .foregroundStyle(LiquidTheme.Palette.tertiary)
                .padding(.top, LiquidTheme.Spacing.xxs)
        }
        .padding(.horizontal, LiquidTheme.Spacing.screenH)
    }

    // MARK: - 行组件

    private func navigationRow(
        icon: String,
        tint: Color,
        title: String,
        value: String?
    ) -> some View {
        HStack(spacing: LiquidTheme.Spacing.sm) {
            iconBadge(icon, tint: tint)

            Text(title)
                .font(LiquidTheme.Typography.rowTitle)
                .foregroundStyle(LiquidTheme.Palette.label)

            Spacer(minLength: LiquidTheme.Spacing.xs)

            if let value {
                Text(value)
                    .font(LiquidTheme.Typography.rowMeta)
                    .foregroundStyle(LiquidTheme.Palette.secondary)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(LiquidTheme.Palette.tertiary)
        }
        .frame(minHeight: LiquidTheme.Hit.row)
        .padding(.horizontal, LiquidTheme.Spacing.md)
        .contentShape(Rectangle())
    }

    private func toggleRow(
        icon: String,
        tint: Color,
        title: String,
        subtitle: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: LiquidTheme.Spacing.sm) {
            iconBadge(icon, tint: tint)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(LiquidTheme.Typography.rowTitle)
                    .foregroundStyle(LiquidTheme.Palette.label)
                Text(subtitle)
                    .font(LiquidTheme.Typography.caption)
                    .foregroundStyle(LiquidTheme.Palette.secondary)
            }

            Spacer(minLength: LiquidTheme.Spacing.xs)

            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(LiquidTheme.Palette.accent)
        }
        .frame(minHeight: LiquidTheme.Hit.row)
        .padding(.horizontal, LiquidTheme.Spacing.md)
        .padding(.vertical, 4)
    }

    private func iconBadge(_ name: String, tint: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(tint, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(LiquidTheme.Palette.separator.opacity(0.5))
            .frame(height: 0.5)
            .padding(.leading, 56)
    }
}

#Preview {
    ProfileView()
        .environment(PlayerModel())
}
