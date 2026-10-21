import Foundation

/// 网易云歌单（用户自己的那些）。
struct NeteasePlaylist: Identifiable, Hashable {
    let id: Int
    let name: String
    let cover: URL?
    let trackCount: Int
    let creator: String
}

/// 网易云登录态。
///
/// 登录走**扫码**（`/login/qr/*`）—— 不在 App 里碰用户密码，
/// 用手机网易云 App 扫一下就完成授权。
///
/// 登录后拿到 `cookie`，后续所有请求都带上它（作为 query 参数），
/// 「每日推荐」之类的账号级接口才有内容。
///
/// ⚠️ cookie 存在 `UserDefaults` 里。正式产品应该放 Keychain ——
/// 这里是为了让演示能跨启动保持登录，方便调试。
@Observable
final class NeteaseSession {

    static let shared = NeteaseSession()

    struct Account: Codable, Hashable {
        let id: Int
        let nickname: String
        let avatarURL: String?
        /// 0 普通 / 10 音乐包 / 11 黑胶 VIP
        let vipType: Int

        var isVIP: Bool { vipType > 0 }

        var membershipText: String {
            switch vipType {
            case 11: return "黑胶 VIP"
            case 10: return "音乐包"
            default: return "普通用户"
            }
        }
    }

    private(set) var cookie: String?
    private(set) var account: Account?
    private(set) var myPlaylists: [NeteasePlaylist] = []
    private(set) var isLoading = false
    private(set) var lastError: String?

    var isLoggedIn: Bool { cookie != nil }

    private let cookieKey = "neteaseCookie"
    private let accountKey = "neteaseAccount"

    private init() {
        // 旧版本把 cookie 存在 UserDefaults 里，读一次迁移到 Keychain
        if let legacy = UserDefaults.standard.string(forKey: cookieKey) {
            Keychain.set(legacy, for: cookieKey)
        }

        // Keychain 优先，读不到再退回 UserDefaults。
        //
        // 为什么要这个兜底：**未签名的模拟器构建，keychain access group 每次安装都可能变**，
        // SecItemCopyMatching 会返回 nil —— 实测重装几次后 cookie 就"丢了"，
        // 但账号信息（UserDefaults）还在，于是界面显示已登录、点进去却弹二维码。
        cookie = Keychain.get(cookieKey) ?? debugFallbackCookie

        if let data = UserDefaults.standard.data(forKey: accountKey) {
            account = try? JSONDecoder().decode(Account.self, from: data)
        }

        // **登录态必须自洽**：没有 cookie 就说明登录已失效，
        // 不能留着账号信息让界面显示"已登录"。
        if cookie == nil, account != nil {
            account = nil
            UserDefaults.standard.removeObject(forKey: accountKey)
        }
    }

    /// 模拟器未签名构建的 keychain access group 每次安装可能变，
    /// `SecItemCopyMatching` 会返回 nil —— 实测重装几次后 cookie 就"丢了"。
    /// 所以 **只在 DEBUG 下**额外存一份到 UserDefaults 兜底。
    /// Release 构建只走 Keychain（凭证不该落在 plist 里）。
    private var debugFallbackCookie: String? {
        #if DEBUG
        return UserDefaults.standard.string(forKey: cookieKey)
        #else
        return nil
        #endif
    }

    // MARK: - 登录 / 登出

    /// 扫码确认后调用：存下 cookie 并拉一次账号信息。
    ///
    /// cookie 存 **Keychain** —— 是凭证，而且卸载 App 不会丢。
    /// 调试期间反复重装不至于每次都要重新扫码。
    func signIn(cookie: String) async {
        self.cookie = cookie
        Keychain.set(cookie, for: cookieKey)
        #if DEBUG
        // 模拟器兜底，见 debugFallbackCookie 的说明。Release 不写。
        UserDefaults.standard.set(cookie, forKey: cookieKey)
        #endif
        await refreshAccount()
    }

    func signOut() {
        cookie = nil
        account = nil
        myPlaylists = []
        lastError = nil
        Keychain.delete(cookieKey)
        UserDefaults.standard.removeObject(forKey: cookieKey)
        UserDefaults.standard.removeObject(forKey: accountKey)
    }

    /// 拉自己的歌单。登录后调用，首页「我的歌单」靠它。
    func loadMyPlaylists() async {
        guard let uid = account?.id else {
            myPlaylists = []
            return
        }
        guard let result = try? await NeteaseAPI.userPlaylists(uid: uid) else { return }
        myPlaylists = result
    }

    /// 拉账号信息。cookie 失效时会清掉登录态。
    func refreshAccount() async {
        guard isLoggedIn else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let json = try await NeteaseAPI.rawGet("/user/account", [:])
            let code = json["code"] as? Int ?? 200

            guard let profile = json["profile"] as? [String: Any],
                  let id = profile["userId"] as? Int,
                  let nickname = profile["nickname"] as? String
            else {
                // **只有明确"未登录"才清 cookie。**
                // 限流、上游抽风、超时都会走到这里，那些情况清掉登录态太粗暴 ——
                // 用户会莫名其妙被登出，还得重新扫码。
                if code == 301 {
                    signOut()
                } else {
                    lastError = "账号信息获取失败（\(code)）"
                }
                return
            }

            let account = Account(
                id: id,
                nickname: nickname,
                avatarURL: (profile["avatarUrl"] as? String)?
                    .replacingOccurrences(of: "http://", with: "https://"),
                vipType: profile["vipType"] as? Int ?? 0
            )
            self.account = account
            lastError = nil
            if let data = try? JSONEncoder().encode(account) {
                UserDefaults.standard.set(data, forKey: accountKey)
            }
            // 账号信息到手后顺手拉歌单，首页直接有内容
            await loadMyPlaylists()
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? "获取账号信息失败"
        }
    }
}
