import Foundation
import Security

/// 极简 Keychain 封装。
///
/// 为什么不用 `UserDefaults`：登录 cookie 是凭证，放 plist 里是明文。
/// Keychain 由系统加密，而且**卸载 App 也不会被清掉** ——
/// 调试期间反复重装不至于每次都要重新扫码。
enum Keychain {

    private static let service = "com.bhands.glassmusicplayer"

    static func set(_ value: String, for key: String) {
        guard let data = value.data(using: .utf8) else { return }

        // 先删再写：SecItemUpdate 在条目不存在时会失败，两步走更省事
        delete(key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            // 首次解锁后可读，锁屏时后台也能用
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }

        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
