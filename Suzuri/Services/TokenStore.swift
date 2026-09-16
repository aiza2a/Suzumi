import Foundation
import Security

/// Keychain 存取封装。
///
/// service = "com.suzuri.app"，account 区分 "access_token" / "short_name"。
/// 项类型 `kSecClassGenericPassword`，可访问性 `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
/// （匿名本地身份，不随 iCloud 同步、首次解锁后可用）。
final class TokenStore {
    static let service = "com.suzuri.app"

    /// 账号键名约定。
    enum Key: String {
        case accessToken = "access_token"
        case shortName = "short_name"
    }

    private let service: String

    init(service: String = TokenStore.service) {
        self.service = service
    }

    // MARK: - Data 级存取

    /// 保存 Data。若已存在则覆盖。
    func save(_ data: Data, for account: String) throws {
        // 先删除旧值，避免重复项。
        delete(account)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unhandledStatus(status)
        }
    }

    /// 读取 Data；不存在返回 nil。
    func load(_ account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    /// 删除项；不存在视为成功。
    func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - String 便捷存取

    func saveString(_ string: String, for account: String) throws {
        try save(Data(string.utf8), for: account)
    }

    func loadString(_ account: String) -> String? {
        guard let data = load(account) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - 错误

    enum KeychainError: Error, Equatable {
        case unhandledStatus(OSStatus)
    }
}