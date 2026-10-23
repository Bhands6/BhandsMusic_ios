import Foundation

/// 网易云歌单（用户自己的那些）。
struct NeteasePlaylist: Identifiable, Hashable {
    let id: Int
    let name: String
    let cover: URL?
    let trackCount: Int
    let creator: String
}

/// 会员等级。
///
/// 为什么要单独一个类型：`/user/account` 的 `vipType` **分不出 VIP 和 SVIP**
/// （黑胶 VIP 和黑胶 SVIP 都返回 11），等级只能问 `/vipinfo`。
/// 界面统一读这个枚举，别再各自去猜 `vipType`。
enum Membership: String, Hashable {
    case none
    case vip
    case svip

    /// 徽标文案：VIP 就显示 VIP，SVIP 就显示 SVIP。
    var title: String {
        switch self {
        case .none: return "普通用户"
        case .vip: return "VIP"
        case .svip: return "SVIP"
        }
    }

    var isMember: Bool { self != .none }

    /// 等级高低。用来判断「这个会员够不够解锁某档音质」——
    /// 比如超清母带要 SVIP，光有 VIP 不够。
    var rank: Int {
        switch self {
        case .none: return 0
        case .vip: return 1
        case .svip: return 2
        }
    }

    /// 当前等级是否覆盖 `required`（SVIP 覆盖 VIP，VIP 不覆盖 SVIP）。
    func covers(_ required: Membership) -> Bool {
        rank >= required.rank
    }

    /// `vipType` 的粗判断 —— 只知道"是不是会员"，分不出等级。
    /// 查 `/vipinfo` 失败时用它兜底，至少不会让真会员显示成普通用户。
    static func coarse(vipType: Int) -> Membership {
        vipType > 0 ? .vip : .none
    }
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
        /// 0 普通 / 10 音乐包 / 11 黑胶（**VIP 和 SVIP 都是 11**，等级看 `membership`）
        let vipType: Int
    }

    private(set) var cookie: String?
    private(set) var account: Account?
    /// 会员等级。真实等级来自 `/vipinfo`，`vipType` 只用来兜底。
    private(set) var membership: Membership = .none
    /// 会员到期时间。nil = 非会员或接口没给。
    private(set) var membershipExpiry: Date?
    private(set) var myPlaylists: [NeteasePlaylist] = []
    private(set) var isLoading = false
    private(set) var lastError: String?

    var isLoggedIn: Bool { cookie != nil }

    private let cookieKey = "neteaseCookie"
    private let accountKey = "neteaseAccount"
    private let membershipKey = "neteaseMembership"
    private let membershipExpiryKey = "neteaseMembershipExpiry"
    /// 上次查会员等级的时间，用来节流（「我的」页每次出现都会问一次）
    private var lastMembershipCheck: Date?

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

        // 会员等级也缓存一份：冷启动还没等到 `/vipinfo` 返回时，
        // 界面先按上次的结果显示，不会闪一下「普通用户」。
        if let raw = UserDefaults.standard.string(forKey: membershipKey) {
            membership = Membership(rawValue: raw) ?? .none
        }
        if let stamp = UserDefaults.standard.object(forKey: membershipExpiryKey) as? Double {
            membershipExpiry = Date(timeIntervalSince1970: stamp / 1000)
        }

        // **登录态必须自洽**：没有 cookie 就说明登录已失效，
        // 不能留着账号信息让界面显示"已登录"。
        if cookie == nil, account != nil {
            account = nil
            UserDefaults.standard.removeObject(forKey: accountKey)
        }
        if cookie == nil {
            membership = .none
            membershipExpiry = nil
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
        membership = .none
        membershipExpiry = nil
        myPlaylists = []
        lastError = nil
        Keychain.delete(cookieKey)
        UserDefaults.standard.removeObject(forKey: cookieKey)
        UserDefaults.standard.removeObject(forKey: accountKey)
        UserDefaults.standard.removeObject(forKey: membershipKey)
        UserDefaults.standard.removeObject(forKey: membershipExpiryKey)
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

            // 先用 `vipType` 给个粗判断（至少知道是不是会员），
            // 再问 `/vipinfo` 拿准确等级 —— 那才是能分出 VIP / SVIP 的接口
            applyMembership(.coarse(vipType: account.vipType), expiry: nil)
            await refreshMembership(force: true)

            // 账号信息到手后顺手拉歌单，首页直接有内容
            await loadMyPlaylists()
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? "获取账号信息失败"
        }
    }

    /// 查会员等级。**需要登录**。
    ///
    /// `/user/account` 的 `vipType` 分不出 VIP 和 SVIP（都是 11），
    /// 真实等级只看 `/vipinfo` 的 `vipCode`。接口失败时退回 `vipType`：
    /// 界面宁可少显示一个「S」，也不能让真会员掉成「普通用户」。
    ///
    /// - Parameter force: 登录 / 手动刷新时传 true；「我的」页每次出现也会调一次，
    ///   那种情况 30 秒内不重复打接口。
    func refreshMembership(force: Bool = false) async {
        guard isLoggedIn else {
            applyMembership(.none, expiry: nil)
            return
        }
        if !force, let last = lastMembershipCheck, Date().timeIntervalSince(last) < 30 {
            return
        }
        lastMembershipCheck = Date()

        let fallback = Membership.coarse(vipType: account?.vipType ?? 0)

        do {
            let info = try await NeteaseAPI.vipInfo()
            if info.isActive {
                applyMembership(info.isSvip ? .svip : .vip, expiry: info.expiry)
            } else if info.vipCode == nil {
                // 接口没给等级（上游抽风 / 字段缺失）—— 保守沿用 vipType
                applyMembership(fallback, expiry: nil)
            } else {
                // 明确给了等级但已过期：vipType 不会跟着过期变，别信它
                applyMembership(.none, expiry: nil)
            }
        } catch {
            applyMembership(fallback, expiry: nil)
        }
    }

    /// 会员状态只从这里改 —— 顺便落盘，冷启动先按上次的结果显示。
    private func applyMembership(_ value: Membership, expiry: Date?) {
        guard membership != value || membershipExpiry != expiry else { return }
        membership = value
        membershipExpiry = expiry
        UserDefaults.standard.set(value.rawValue, forKey: membershipKey)
        if let expiry {
            UserDefaults.standard.set(expiry.timeIntervalSince1970 * 1000, forKey: membershipExpiryKey)
        } else {
            UserDefaults.standard.removeObject(forKey: membershipExpiryKey)
        }
    }
}
