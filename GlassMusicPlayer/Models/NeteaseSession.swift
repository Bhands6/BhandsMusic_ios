import Foundation

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
    private(set) var isLoading = false
    private(set) var lastError: String?

    var isLoggedIn: Bool { cookie != nil }

    private let cookieKey = "neteaseCookie"
    private let accountKey = "neteaseAccount"

    private init() {
        cookie = UserDefaults.standard.string(forKey: cookieKey)
        if let data = UserDefaults.standard.data(forKey: accountKey) {
            account = try? JSONDecoder().decode(Account.self, from: data)
        }
    }

    // MARK: - 登录 / 登出

    /// 扫码确认后调用：存下 cookie 并拉一次账号信息。
    func signIn(cookie: String) async {
        self.cookie = cookie
        UserDefaults.standard.set(cookie, forKey: cookieKey)
        await refreshAccount()
    }

    func signOut() {
        cookie = nil
        account = nil
        lastError = nil
        UserDefaults.standard.removeObject(forKey: cookieKey)
        UserDefaults.standard.removeObject(forKey: accountKey)
    }

    /// 拉账号信息。cookie 失效时会清掉登录态。
    func refreshAccount() async {
        guard isLoggedIn else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let json = try await NeteaseAPI.rawGet("/user/account", [:])
            guard let profile = json["profile"] as? [String: Any],
                  let id = profile["userId"] as? Int,
                  let nickname = profile["nickname"] as? String
            else {
                // 没拿到 profile 说明 cookie 已经无效了
                signOut()
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
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? "获取账号信息失败"
        }
    }
}
