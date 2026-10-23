import SwiftUI

/// 音质档位。直接对应网易云 `/song/url/v1` 的 `level` 参数。
///
/// **声明顺序就是界面顺序，从高到低**。带 `requiresMembership` 的档位只有会员看得见 ——
/// 非会员选了也拿不到地址（接口会退回低码率，或者干脆给空 url）。
enum AudioQuality: String, CaseIterable, Identifiable {
    case jymaster
    case sky
    case hires
    case lossless
    case high
    case standard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .jymaster: return "超清母带"
        case .sky: return "沉浸环绕声"
        case .hires: return "Hi-Res"
        case .lossless: return "无损"
        case .high: return "高品质"
        case .standard: return "标准"
        }
    }

    var subtitle: String {
        switch self {
        case .jymaster: return "母带级 · SVIP 专属"
        case .sky: return "空间音频 · 会员专属"
        case .hires: return "高解析度无损 · 会员专属"
        case .lossless: return "FLAC · 文件大，音质最好"
        case .high: return "320kbps · 默认"
        case .standard: return "128kbps · 省流量"
        }
    }

    var neteaseLevel: String {
        switch self {
        case .jymaster: return "jymaster"
        case .sky: return "sky"
        case .hires: return "hires"
        case .lossless: return "lossless"
        case .high: return "exhigh"
        case .standard: return "standard"
        }
    }

    /// 解锁这一档需要什么等级。
    ///
    /// 网易云的分档（2026 年的权益）：
    /// - **沉浸环绕声 / Hi-Res**：黑胶 VIP 就有；
    /// - **超清母带**（192kHz/24bit）：SVIP 的核心卖点，VIP 用不了；
    /// - 无损 / 高品质 / 标准：免费。
    ///
    /// 无损这里仍对所有人开放 —— 沿用 App 原有行为，没跟着网易云的 VIP 限制走。
    var requiredTier: Membership {
        switch self {
        case .jymaster: return .svip
        case .sky, .hires: return .vip
        case .lossless, .high, .standard: return .none
        }
    }

    /// 会员才有权限的档位（列表里要挂金标的那种）。
    var requiresMembership: Bool { requiredTier != .none }

    /// 当前会员等级能不能选这一档。
    func isUnlocked(for tier: Membership) -> Bool {
        tier.covers(requiredTier)
    }

    /// 当前档位。存 UserDefaults，重开 App 还在。
    static var current: AudioQuality {
        get { AudioQuality(rawValue: UserDefaults.standard.string(forKey: "audioQuality") ?? "") ?? .high }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "audioQuality") }
    }

    /// 实际生效的档位。
    ///
    /// 会员过期或降级后 `current` 可能还停在高档位上（比如 SVIP 掉了还选着超清母带）——
    /// 这时候退回高品质，否则每次请求都拿不到播放地址。续费之后原来的选择会自动回来。
    static var effective: AudioQuality {
        let selected = AudioQuality.current
        guard selected.isUnlocked(for: NeteaseSession.shared.membership) else {
            return .high
        }
        return selected
    }
}

/// 「我的」页里导航行点进去看到的内容。
enum ProfileDetail: String, Identifiable {
    case quality
    case downloads
    case about
    case account
    case server

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quality: return "音质与下载"
        case .downloads: return "音乐库"
        case .about: return "关于 BhandsMusic"
        case .account: return "账号与安全"
        case .server: return "服务器"
        }
    }
}

/// 「我的」页可能弹出的浮层，**合并成一个枚举是必须的**。
///
/// 同一个视图上挂两个 `.sheet` 时 SwiftUI 只认最后一个 ——
/// 之前账户卡明明设了"打开账号详情"，弹出的却是后挂的登录二维码。
enum ProfileSheet: Identifiable {
    case detail(ProfileDetail)
    case login

    var id: String {
        switch self {
        case .detail(let detail): return detail.id
        case .login: return "login"
        }
    }
}

/// 统一的详情浮层 —— 四个导航行共用一套外壳，只换内容。
struct ProfileDetailSheet: View {
    let detail: ProfileDetail

    @Environment(\.dismiss) private var dismiss
    @Environment(NeteaseSession.self) private var session
    @Environment(LibraryStore.self) private var library
    @Environment(PlaylistStore.self) private var playlists
    @State private var quality = AudioQuality.effective
    @State private var serverURL = ServerSettings.baseURLString
    @State private var apiKey = ServerSettings.apiKey
    @State private var probeState: ProbeState = .idle

    enum ProbeState: Equatable {
        case idle, testing, ok, failed(String)
    }

    var body: some View {
        ZStack(alignment: .top) {
            SoftCanvas()

            ScrollView {
                VStack(alignment: .leading, spacing: LiquidTheme.Spacing.lg) {
                    header
                    content
                }
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        // **必须是 [.large]**。用 [.medium, .large] 时，
        // 内容比 medium 高的那两个（关于、音乐库）sheet 会**完全不弹** ——
        // 点了没反应，而且不报错。实测「关于」和「音乐库」都是这样。
        .presentationDetents([.large])
        .presentationBackground(.clear)
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        HStack {
            Text(detail.title)
                .font(LiquidTheme.Typography.screen)
                .foregroundStyle(LiquidTheme.Palette.label)

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(LiquidTheme.Palette.label)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(LiquidTheme.Palette.panelFill))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("关闭"))
        }
        .padding(.horizontal, LiquidTheme.Spacing.screenH)
    }

    @ViewBuilder
    private var content: some View {
        switch detail {
        case .quality: qualityContent
        case .downloads: downloadsContent
        case .about: aboutContent
        case .account: accountContent
        case .server: serverContent
        }
    }

    // MARK: - 服务器

    private var serverContent: some View {
        VStack(alignment: .leading, spacing: LiquidTheme.Spacing.sm) {
            VStack(spacing: 0) {
                fieldRow("地址", placeholder: "https://api.example.com", text: $serverURL)
                divider
                fieldRow("密钥", placeholder: "留空表示服务端未开鉴权", text: $apiKey)
            }
            .glassPanel()
            .padding(.horizontal, LiquidTheme.Spacing.screenH)

            HStack(spacing: LiquidTheme.Spacing.sm) {
                Button {
                    ServerSettings.baseURLString = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    ServerSettings.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    Task {
                        // 探活通过才算真接上了后端，这时把数据全部重拉 ——
                        // 否则 PlaylistStore 的 loadAll 闩锁已消费（只试一次），
                        // 「为你推荐」会一直停在旧地址拉到的/兜底的旧内容上。
                        if await probe() {
                            await playlists.reload()
                            await session.loadMyPlaylists()
                        }
                    }
                } label: {
                    Text("保存并测试")
                        .font(LiquidTheme.Typography.button)
                        .foregroundStyle(LiquidTheme.Palette.onAccent)
                        .frame(maxWidth: .infinity)
                        .frame(height: LiquidTheme.Hit.control)
                        .background(Capsule().fill(LiquidTheme.Palette.accent))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, LiquidTheme.Spacing.screenH)

            probeLine

            Text("模拟器可以用 localhost；真机要填局域网 IP（如 http://192.168.1.5:3000）或部署后的域名。\n用 HTTPS 的话不需要额外配置。")
                .font(LiquidTheme.Typography.caption)
                .foregroundStyle(LiquidTheme.Palette.tertiary)
                .padding(.horizontal, LiquidTheme.Spacing.screenH)
        }
    }

    @ViewBuilder
    private var probeLine: some View {
        switch probeState {
        case .idle:
            EmptyView()
        case .testing:
            Label("正在测试…", systemImage: "clock")
                .font(LiquidTheme.Typography.caption)
                .foregroundStyle(LiquidTheme.Palette.secondary)
                .padding(.horizontal, LiquidTheme.Spacing.screenH)
        case .ok:
            Label("连接正常", systemImage: "checkmark.circle.fill")
                .font(LiquidTheme.Typography.caption)
                .foregroundStyle(Color(hex: 0x00B894))
                .padding(.horizontal, LiquidTheme.Spacing.screenH)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(LiquidTheme.Typography.caption)
                .foregroundStyle(Color(hex: 0xD63031))
                .padding(.horizontal, LiquidTheme.Spacing.screenH)
        }
    }

    private func fieldRow(_ title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(LiquidTheme.Typography.rowMeta)
                .foregroundStyle(LiquidTheme.Palette.secondary)

            TextField(placeholder, text: text)
                .font(LiquidTheme.Typography.rowTitle)
                .foregroundStyle(LiquidTheme.Palette.label)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
        }
        .padding(.horizontal, LiquidTheme.Spacing.md)
        .padding(.vertical, 10)
    }

    /// 打一次 `/healthz`。这个接口不需要鉴权，专门用来探活。
    /// - Returns: 服务可用（且密钥齐备）时返回 `true`，调用方据此决定要不要重拉数据。
    private func probe() async -> Bool {
        probeState = .testing

        guard let base = URL(string: ServerSettings.baseURLString) else {
            probeState = .failed("地址格式不对")
            return false
        }

        var request = URLRequest(url: base.appendingPathComponent("healthz"))
        request.timeoutInterval = 8

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                probeState = .failed("服务返回 \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                return false
            }
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let needsKey = json?["authRequired"] as? Bool ?? false
            if needsKey && ServerSettings.apiKey.isEmpty {
                probeState = .failed("服务已开鉴权，请填写密钥")
                return false
            }
            probeState = .ok
            return true
        } catch {
            probeState = .failed("连不上：\(error.localizedDescription)")
            return false
        }
    }

    // MARK: - 音质

    private var qualityContent: some View {
        VStack(alignment: .leading, spacing: LiquidTheme.Spacing.sm) {
            Text(session.membership.isMember
                 ? "选择在线播放的码率。沉浸环绕声、Hi-Res 为黑胶 VIP 权益，超清母带为黑胶 SVIP 专属。"
                 : "选择在线播放的码率。改动立即生效，下一首开始按新档位请求。")
                .font(LiquidTheme.Typography.caption)
                .foregroundStyle(LiquidTheme.Palette.secondary)
                .padding(.horizontal, LiquidTheme.Spacing.screenH)

            VStack(spacing: 0) {
                ForEach(Array(availableQualities.enumerated()), id: \.element.id) { index, option in
                    if index > 0 { divider }

                    Button {
                        quality = option
                        AudioQuality.current = option
                    } label: {
                        HStack(spacing: LiquidTheme.Spacing.sm) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 5) {
                                    Text(option.title)
                                        .font(LiquidTheme.Typography.rowTitle)
                                        .foregroundStyle(LiquidTheme.Palette.label)

                                    // 会员专属档位挂金标：VIP 浅金、SVIP 亮金，和「我的」页同一套视觉
                                    if option.requiresMembership {
                                        MembershipTag(tier: option.requiredTier)
                                    }
                                }
                                Text(option.subtitle)
                                    .font(LiquidTheme.Typography.rowMeta)
                                    .foregroundStyle(LiquidTheme.Palette.secondary)
                            }

                            Spacer(minLength: 0)

                            if quality == option {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(LiquidTheme.Palette.accent)
                            }
                        }
                        .frame(minHeight: LiquidTheme.Hit.row)
                        .padding(.horizontal, LiquidTheme.Spacing.md)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .glassPanel()
            .padding(.horizontal, LiquidTheme.Spacing.screenH)
        }
    }

    /// 只列出当前会员等级解锁得了的档位：普通用户看不到会员档，
    /// VIP 看得到沉浸环绕声 / Hi-Res，超清母带要 SVIP。
    /// 会员状态一变（比如刚续费），`session` 是 @Observable，列表会自己刷新。
    private var availableQualities: [AudioQuality] {
        AudioQuality.allCases.filter { $0.isUnlocked(for: session.membership) }
    }

    // MARK: - 已下载

    private var downloadsContent: some View {
        VStack(alignment: .leading, spacing: LiquidTheme.Spacing.sm) {
            Text("当前音乐库的曲目。")
                .font(LiquidTheme.Typography.caption)
                .foregroundStyle(LiquidTheme.Palette.secondary)
                .padding(.horizontal, LiquidTheme.Spacing.screenH)

            VStack(spacing: 0) {
                ForEach(Array(library.songs.enumerated()), id: \.element.id) { index, song in
                    if index > 0 { divider }

                    HStack(spacing: LiquidTheme.Spacing.sm) {
                        ArtworkView(name: song.artworkName, cornerRadius: 8)
                            .frame(width: 40, height: 40)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(song.title)
                                .font(LiquidTheme.Typography.rowTitle)
                                .foregroundStyle(LiquidTheme.Palette.label)
                                .lineLimit(1)
                            Text(song.artist)
                                .font(LiquidTheme.Typography.rowMeta)
                                .foregroundStyle(LiquidTheme.Palette.secondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 0)

                        Text(song.durationText)
                            .font(LiquidTheme.Typography.rowMeta)
                            .foregroundStyle(LiquidTheme.Palette.tertiary)
                    }
                    .frame(minHeight: LiquidTheme.Hit.row)
                    .padding(.horizontal, LiquidTheme.Spacing.md)
                }
            }
            .glassPanel()
            .padding(.horizontal, LiquidTheme.Spacing.screenH)
        }
    }

    // MARK: - 关于

    private var aboutContent: some View {
        VStack(alignment: .leading, spacing: LiquidTheme.Spacing.md) {
            VStack(spacing: LiquidTheme.Spacing.xs) {
                // 用真正的桌面图标，不再是 SF Symbol
                Image("app_icon")
                    .resizable()
                    .frame(width: 68, height: 68)
                    // iOS 图标圆角 ≈ 边长 × 0.2237
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                    }
                    .shadow(color: .black.opacity(0.16), radius: 10, y: 4)

                Text("BhandsMusic")
                    .font(LiquidTheme.Typography.section)
                    .foregroundStyle(LiquidTheme.Palette.label)

                Text("v1.0.0 (1)")
                    .font(LiquidTheme.Typography.rowMeta)
                    .foregroundStyle(LiquidTheme.Palette.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, LiquidTheme.Spacing.md)

            VStack(spacing: 0) {
                infoRow("音源", "打包音轨 · 网络电台 · 网易云")
                divider
                infoRow("音轨", "\(library.songs.count) 首可播曲目")
                divider
                infoRow("电台", "\(RadioCatalog.stations.count) 个公开直播流")
                divider
                infoRow("界面", "SwiftUI · 液态玻璃")
            }
            .glassPanel()
            .padding(.horizontal, LiquidTheme.Spacing.screenH)

            Text("网易云曲库来自非官方接口，仅供个人学习，版权归网易云所有。")
                .font(LiquidTheme.Typography.caption)
                .foregroundStyle(LiquidTheme.Palette.tertiary)
                .padding(.horizontal, LiquidTheme.Spacing.screenH)
        }
    }

    // MARK: - 账户

    private var accountContent: some View {
        VStack(alignment: .leading, spacing: LiquidTheme.Spacing.sm) {
            VStack(spacing: 0) {
                infoRow("用户名", session.account?.nickname ?? "未登录")
                divider
                // 等级来自 `/vipinfo`，不是 `vipType` —— 后者分不出 VIP / SVIP
                infoRow("会员", session.isLoggedIn ? session.membership.title : "—")
                if let expiry = session.membershipExpiry, session.membership.isMember {
                    divider
                    infoRow("会员到期", expiry.formatted(.dateTime.year().month().day()))
                }
                divider
                infoRow("网易云 UID", session.account.map { String($0.id) } ?? "—")
                divider
                infoRow("登录方式", session.isLoggedIn ? "扫码登录" : "—")
            }
            .glassPanel()
            .padding(.horizontal, LiquidTheme.Spacing.screenH)

            Text(session.isLoggedIn
                 ? "登录态保存在本机，「每日推荐」会按这个账号生成。"
                 : "在「我的」页点头像卡片即可扫码登录。")
                .font(LiquidTheme.Typography.caption)
                .foregroundStyle(LiquidTheme.Palette.tertiary)
                .padding(.horizontal, LiquidTheme.Spacing.screenH)
        }
    }

    // MARK: - 零件

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(LiquidTheme.Typography.rowTitle)
                .foregroundStyle(LiquidTheme.Palette.label)
            Spacer(minLength: LiquidTheme.Spacing.xs)
            Text(value)
                .font(LiquidTheme.Typography.rowMeta)
                .foregroundStyle(LiquidTheme.Palette.secondary)
                .multilineTextAlignment(.trailing)
        }
        .frame(minHeight: LiquidTheme.Hit.row)
        .padding(.horizontal, LiquidTheme.Spacing.md)
    }

    private var divider: some View {
        Rectangle()
            .fill(LiquidTheme.Palette.separator.opacity(0.5))
            .frame(height: 0.5)
            .padding(.leading, LiquidTheme.Spacing.md)
    }
}
