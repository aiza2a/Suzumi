import CryptoKit
import Foundation
import Security

/// Keychain 存取封装。
///
/// service = "com.suzuri.app"，account 区分 "access_token" / "short_name"。
/// 匿名本地身份不随 iCloud 同步、首次解锁后可用。
final class TokenStore {
    static let service = "com.suzuri.app"

    /// 账号键名约定。
    enum Key: String, Sendable {
        case accessToken = "access_token"
        case shortName = "short_name"
    }

    private let service: String

    init(service: String = TokenStore.service) {
        self.service = service
    }

    // MARK: - Origin-scoped account keys

    /// Returns the URL origin used to isolate credentials between mirrors.
    static func origin(for baseURL: URL) -> String {
        guard let scheme = baseURL.scheme?.lowercased(),
              let host = baseURL.host?.lowercased()
        else {
            return baseURL.absoluteString.lowercased()
        }

        var result = "\(scheme)://\(host)"
        if let port = baseURL.port,
           !((scheme == "https" && port == 443) || (scheme == "http" && port == 80)) {
            result += ":\(port)"
        }
        return result
    }

    static func origin(for baseURL: String) -> String {
        guard let url = URL(string: baseURL) else {
            return baseURL.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        return origin(for: url)
    }

    /// Stable, non-reversible identifier used in Keychain account names and cache scopes.
    static func fingerprint(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    static func scopedAccount(_ key: Key, origin: String) -> String {
        "\(key.rawValue)_\(fingerprint(origin))"
    }

    func saveString(_ string: String, for key: Key, origin: String) throws {
        try saveString(string, for: Self.scopedAccount(key, origin: origin))
    }

    func loadString(_ key: Key, origin: String) -> String? {
        loadString(Self.scopedAccount(key, origin: origin))
    }

    func delete(_ key: Key, origin: String) {
        delete(Self.scopedAccount(key, origin: origin))
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
