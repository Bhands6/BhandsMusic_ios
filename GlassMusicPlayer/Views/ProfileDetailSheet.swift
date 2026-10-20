import SwiftUI

/// 音质档位。直接对应网易云 `/song/url/v1` 的 `level` 参数。
enum AudioQuality: String, CaseIterable, Identifiable {
    case lossless
    case high
    case standard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lossless: return "无损"
        case .high: return "高品质"
        case .standard: return "标准"
        }
    }

    var subtitle: String {
        switch self {
        case .lossless: return "FLAC · 文件大，音质最好"
        case .high: return "320kbps · 默认"
        case .standard: return "128kbps · 省流量"
        }
    }

    var neteaseLevel: String {
        switch self {
        case .lossless: return "lossless"
        case .high: return "exhigh"
        case .standard: return "standard"
        }
    }

    /// 当前档位。存 UserDefaults，重开 App 还在。
    static var current: AudioQuality {
        get { AudioQuality(rawValue: UserDefaults.standard.string(forKey: "audioQuality") ?? "") ?? .high }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "audioQuality") }
    }
}

/// 「我的」页里导航行点进去看到的内容。
enum ProfileDetail: String, Identifiable {
    case quality
    case downloads
    case about
    case account

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quality: return "音质与下载"
        case .downloads: return "已下载"
        case .about: return "关于 BhandsMusic"
        case .account: return "账号与安全"
        }
    }
}

/// 统一的详情浮层 —— 四个导航行共用一套外壳，只换内容。
struct ProfileDetailSheet: View {
    let detail: ProfileDetail

    @Environment(\.dismiss) private var dismiss
    @State private var quality = AudioQuality.current

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
        .presentationDetents([.medium, .large])
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
        }
    }

    // MARK: - 音质

    private var qualityContent: some View {
        VStack(alignment: .leading, spacing: LiquidTheme.Spacing.sm) {
            Text("选择在线播放的码率。改动立即生效，下一首开始按新档位请求。")
                .font(LiquidTheme.Typography.caption)
                .foregroundStyle(LiquidTheme.Palette.secondary)
                .padding(.horizontal, LiquidTheme.Spacing.screenH)

            VStack(spacing: 0) {
                ForEach(Array(AudioQuality.allCases.enumerated()), id: \.element.id) { index, option in
                    if index > 0 { divider }

                    Button {
                        quality = option
                        AudioQuality.current = option
                    } label: {
                        HStack(spacing: LiquidTheme.Spacing.sm) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.title)
                                    .font(LiquidTheme.Typography.rowTitle)
                                    .foregroundStyle(LiquidTheme.Palette.label)
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

    // MARK: - 已下载

    private var downloadsContent: some View {
        VStack(alignment: .leading, spacing: LiquidTheme.Spacing.sm) {
            Text("打包在 App 里的音轨，离线可播。")
                .font(LiquidTheme.Typography.caption)
                .foregroundStyle(LiquidTheme.Palette.secondary)
                .padding(.horizontal, LiquidTheme.Spacing.screenH)

            VStack(spacing: 0) {
                ForEach(Array(MusicLibrary.songs.enumerated()), id: \.element.id) { index, song in
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
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(LiquidTheme.Palette.accent)

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
                infoRow("音轨", "8 首自合成环境音乐")
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
                infoRow("用户名", "夜行者_K")
                divider
                infoRow("会员", "BhandsMusic 会员")
                divider
                infoRow("有效期至", "2027-03-18")
                divider
                infoRow("登录方式", "Apple ID")
            }
            .glassPanel()
            .padding(.horizontal, LiquidTheme.Spacing.screenH)

            Text("演示版本没有接入真实账号体系，以上信息为示例数据。")
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
