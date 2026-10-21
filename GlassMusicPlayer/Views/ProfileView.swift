import SwiftUI

/// 我的 —— 账户与设置。整页只有悬浮头部是玻璃，其余全是实底分组卡片。
struct ProfileView: View {
    @Environment(PlayerModel.self) private var player
    @Environment(PlaylistStore.self) private var playlists
    @Environment(LibraryStore.self) private var library
    @Environment(NeteaseSession.self) private var session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var scrollOffset: CGFloat = 0
    @State private var sleepTimerOn = false
    /// 睡眠定时的计时任务。非 nil 就表示"正在倒计时"。
    @State private var sleepTask: Task<Void, Never>?
    @State private var detail: ProfileDetail?
    @State private var showsLogoutConfirm = false
    @State private var showsLogin = false

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
                HeaderIconButton(systemName: "gearshape") {
                    detail = .about
                }
            }
            .padding(.horizontal, LiquidTheme.Spacing.md)
            .padding(.top, 4)
        }
        .sheet(item: $detail) { item in
            ProfileDetailSheet(detail: item)
                .environment(player)
        }
        .onAppear {
            // 截图用：-detail <name> 直接打开某个浮层（login 是扫码登录页）
            guard let raw = DebugLaunch.profileDetail else { return }
            if raw == "login" {
                showsLogin = true
            } else if let parsed = ProfileDetail(rawValue: raw) {
                detail = parsed
            }
        }
        .sheet(isPresented: $showsLogin) {
            NeteaseLoginSheet()
                .environment(playlists)
        }
        .confirmationDialog("退出登录", isPresented: $showsLogoutConfirm, titleVisibility: .visible) {
            Button("退出登录", role: .destructive) {
                session.signOut()
                Task { await playlists.reload() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("会清除本机保存的网易云登录态，「每日推荐」将退回通用榜单。")
        }
    }

    /// 睡眠定时开关。打开就起一个 30 分钟的任务，到点暂停播放。
    private var sleepBinding: Binding<Bool> {
        Binding(
            get: { sleepTask != nil },
            set: { isOn in
                sleepTask?.cancel()
                sleepTask = nil
                guard isOn else { return }

                sleepTask = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(30 * 60))
                    guard !Task.isCancelled else { return }
                    if player.isPlaying { player.togglePlayPause() }
                    sleepTask = nil
                }
            }
        )
    }

    // MARK: - 标题

    private var titleBlock: some View {
        Text("我的")
            .font(LiquidTheme.Typography.hero)
            .foregroundStyle(LiquidTheme.Palette.label)
            .padding(.horizontal, LiquidTheme.Spacing.screenH)
    }

    // MARK: - 账户卡

    /// 账户卡。未登录时显示「点击登录」，登录后显示网易云账号的真实信息。
    private var profileCard: some View {
        Button {
            if session.isLoggedIn {
                detail = .account
            } else {
                showsLogin = true
            }
        } label: {
            HStack(spacing: LiquidTheme.Spacing.md) {
                avatar

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(session.account?.nickname ?? "未登录")
                            .font(LiquidTheme.Typography.section)
                            .foregroundStyle(LiquidTheme.Palette.label)
                            .lineLimit(1)

                        if let account = session.account, account.isVIP {
                            Text(account.membershipText)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(LiquidTheme.Palette.onAccent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(LiquidTheme.Palette.accent))
                        }
                    }

                    Text(subtitleText)
                        .font(LiquidTheme.Typography.caption)
                        .foregroundStyle(LiquidTheme.Palette.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LiquidTheme.Palette.tertiary)
            }
            .padding(LiquidTheme.Spacing.md)
            .glassPanel()
            .padding(.horizontal, LiquidTheme.Spacing.screenH)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 服务器地址只显示主机名，太长会把行挤爆
    private var serverSummary: String {
        guard let url = URL(string: ServerSettings.baseURLString), let host = url.host else {
            return "未配置"
        }
        if url.port == 80 || url.port == 443 || url.port == nil {
            return host
        }
        return "\(host):\(url.port!)"
    }

    private var subtitleText: String {        guard let account = session.account else {
            return session.isLoading ? "正在获取账号信息…" : "点击登录网易云音乐"
        }
        return "网易云 UID \(account.id) · \(account.membershipText)"
    }

    @ViewBuilder
    private var avatar: some View {
        Group {
            if let raw = session.account?.avatarURL, let url = URL(string: raw) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Image("avatar_rider").resizable().scaledToFill()
                    }
                }
            } else {
                Image("avatar_rider").resizable().scaledToFill()
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(Circle())
        .overlay {
            Circle().strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5)
        }
    }

    // MARK: - 统计

    private var statsCard: some View {
        HStack(spacing: 0) {
            // 三个数字都得是真的：之前「+126」和「36h」都是编的
            stat(value: "\(player.likedIDs.count)", label: "收藏歌曲")
            divider
            stat(value: "\(session.myPlaylists.isEmpty ? MusicLibrary.playlists.count : session.myPlaylists.count)", label: "我的歌单")
            divider
            stat(value: "\(library.songs.count)", label: "曲库歌曲")
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
                    value: AudioQuality.current.title
                ) {
                    detail = .quality
                }

                rowDivider

                toggleRow(
                    icon: "moon.zzz.fill",
                    tint: Color(hex: 0x6C5CE7),
                    title: "睡眠定时",
                    subtitle: sleepTimerOn ? "30 分钟后停止播放" : "关闭",
                    isOn: sleepBinding
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
                ) {
                    detail = .account
                }

                rowDivider

                navigationRow(
                    icon: "arrow.down.circle.fill",
                    tint: Color(hex: 0x0984E3),
                    title: "音乐库",
                    value: "\(library.songs.count) 首"
                ) {
                    detail = .downloads
                }

                rowDivider

                navigationRow(
                    icon: "network",
                    tint: Color(hex: 0x00B894),
                    title: "服务器",
                    value: serverSummary
                ) {
                    detail = .server
                }

                rowDivider

                navigationRow(
                    icon: "info.circle.fill",
                    tint: LiquidTheme.Palette.secondary,
                    title: "关于 BhandsMusic",
                    value: "v1.0.0"
                ) {
                    detail = .about
                }
            }
            .glassPanel()
            .padding(.horizontal, LiquidTheme.Spacing.screenH)
        }
    }

    private var footer: some View {
        VStack(spacing: LiquidTheme.Spacing.xs) {
            Button {
                showsLogoutConfirm = true
            } label: {
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

    /// 可点击的导航行。
    /// 之前这里只是个 `HStack` + 箭头 —— 根本没有 `Button`，点了完全没反应。
    private func navigationRow(
        icon: String,
        tint: Color,
        title: String,
        value: String?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
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
        .buttonStyle(.plain)
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
