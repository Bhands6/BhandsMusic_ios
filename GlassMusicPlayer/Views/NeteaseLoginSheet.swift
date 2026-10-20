import SwiftUI

/// 网易云扫码登录。
///
/// 为什么用扫码而不是账号密码：**App 里不该经手用户密码**。
/// 扫码把授权交给网易云自己的 App，我们只拿一个 cookie。
struct NeteaseLoginSheet: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(PlaylistStore.self) private var playlists

    @State private var qrImage: UIImage?
    @State private var state: NeteaseAPI.QRState = .waiting
    @State private var errorText: String?
    @State private var pollTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .top) {
            SoftCanvas()

            VStack(spacing: LiquidTheme.Spacing.lg) {
                header

                Spacer(minLength: 0)

                qrCard

                statusText

                Spacer(minLength: 0)

                footnote
            }
            .padding(.top, 20)
            .padding(.bottom, 32)
        }
        .presentationDetents([.large])
        .presentationBackground(.clear)
        .presentationDragIndicator(.visible)
        .task { await start() }
        .onDisappear { pollTask?.cancel() }
    }

    private var header: some View {
        HStack {
            Text("登录网易云音乐")
                .font(LiquidTheme.Typography.section)
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

    private var qrCard: some View {
        VStack(spacing: LiquidTheme.Spacing.sm) {
            Group {
                if let qrImage {
                    Image(uiImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                } else {
                    ProgressView()
                        .frame(width: 220, height: 220)
                }
            }
            .frame(width: 220, height: 220)
            .padding(14)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            // 二维码快过期 / 已过期时压暗，给用户明确的"重扫"信号
            .opacity(isStale ? 0.25 : 1)
            .overlay {
                if isStale {
                    Button("刷新二维码") { Task { await start() } }
                        .font(LiquidTheme.Typography.button)
                        .foregroundStyle(LiquidTheme.Palette.onAccent)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(LiquidTheme.Palette.accent))
                }
            }
        }
    }

    @ViewBuilder
    private var statusText: some View {
        if let errorText {
            Text(errorText)
                .font(LiquidTheme.Typography.rowMeta)
                .foregroundStyle(Color(hex: 0xD63031))
                .multilineTextAlignment(.center)
                .padding(.horizontal, LiquidTheme.Spacing.xl)
        } else {
            Text(statusMessage)
                .font(LiquidTheme.Typography.rowTitle)
                .foregroundStyle(LiquidTheme.Palette.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, LiquidTheme.Spacing.xl)
        }
    }

    private var footnote: some View {
        Text("用网易云音乐 App 扫码并确认。\n登录后「每日推荐」等会按你的账号生成。")
            .font(LiquidTheme.Typography.caption)
            .foregroundStyle(LiquidTheme.Palette.tertiary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, LiquidTheme.Spacing.xl)
    }

    // MARK: - 状态

    private var isStale: Bool {
        if case .expired = state { return true }
        return false
    }

    private var statusMessage: String {
        switch state {
        case .expired: return "二维码已过期"
        case .waiting: return "打开网易云音乐 App 扫码"
        case .scanned: return "已扫码，请在手机上确认"
        case .authorized: return "登录成功"
        }
    }

    // MARK: - 流程

    private func start() async {
        errorText = nil
        pollTask?.cancel()
        state = .waiting

        do {
            let login = try await NeteaseAPI.qrLoginKey()
            qrImage = Self.decode(login.imageDataURL)

            let key = login.key
            pollTask = Task { @MainActor in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(2))
                    guard !Task.isCancelled else { return }

                    guard let next = try? await NeteaseAPI.qrCheck(key: key) else { continue }
                    state = next

                    switch next {
                    case .authorized(let cookie):
                        await NeteaseSession.shared.signIn(cookie: cookie)
                        // 登录后「每日推荐」要按账号重拉一遍
                        await playlists.reload()
                        dismiss()
                        return
                    case .expired:
                        return
                    default:
                        continue
                    }
                }
            }
        } catch {
            errorText = "获取二维码失败，检查 API 服务是否在运行"
        }
    }

    /// `qrimg` 是 `data:image/png;base64,...`，剥掉前缀再解码。
    private static func decode(_ dataURL: String) -> UIImage? {
        let base64 = dataURL.components(separatedBy: "base64,").last ?? dataURL
        guard let data = Data(base64Encoded: base64) else { return nil }
        return UIImage(data: data)
    }
}
