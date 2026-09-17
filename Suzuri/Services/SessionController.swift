import Foundation
import Observation

/// 启动会话与匿名账号生命周期。
@Observable
@MainActor
final class SessionController {
    static let authorNameKey = "author_name"
    static let authorURLKey = "author_url"

    let serverManager: ServerManager

    @ObservationIgnored
    private let tokenStore: TokenStore
    @ObservationIgnored
    private let session: URLSession

    private(set) var accessToken: String?
    private(set) var shortName: String?
    private(set) var authorName: String?
    private(set) var authorURL: String?
    private(set) var isLoading = false
    private(set) var isLoaded = false

    var isAnonymous: Bool { accessToken == nil }

    init(
        serverManager: ServerManager = ServerManager(),
        tokenStore: TokenStore = TokenStore(),
        session: URLSession = .shared
    ) {
        self.serverManager = serverManager
        self.tokenStore = tokenStore
        self.session = session
        self.accessToken = tokenStore.loadString(TokenStore.Key.accessToken.rawValue)
        self.shortName = tokenStore.loadString(TokenStore.Key.shortName.rawValue)
        self.authorName = tokenStore.loadString(Self.authorNameKey)
        self.authorURL = tokenStore.loadString(Self.authorURLKey)
    }

    /// 加载本地 token，并尽力校验账号；校验失败不阻塞匿名使用。
    func load() async {
        guard !isLoaded else { return }
        isLoading = true
        defer {
            isLoading = false
            isLoaded = true
        }

        guard accessToken != nil else { return }
        do {
            let account = try await AccountService(client: makeClient()).getAccountInfo()
            apply(account)
        } catch let error as TelegraphError {
            if case .api(let message) = error,
               message.uppercased().contains("ACCESS_TOKEN") {
                clearLocalAccess()
            }
            // Temporary transport failures keep the local token for a later retry.
        } catch {
            // Unknown validation failures do not block anonymous use.
        }
    }

    /// 返回当前 APIClient；没有 token 时仍可读取公开页面。
    func makeClient() -> APIClient {
        let baseURL = serverManager.apiURL ?? URL(string: MirrorFallback.apiBase)!
        return APIClient(baseURL: baseURL, session: session, accessToken: accessToken)
    }

    /// Returns a client for an arbitrary mirror, useful for previews and tests.
    func makeClient(serverManager: ServerManager) -> APIClient {
        let baseURL = serverManager.apiURL ?? URL(string: MirrorFallback.apiBase)!
        return APIClient(baseURL: baseURL, session: session, accessToken: accessToken)
    }

    /// 首次发布时才创建匿名账号，并把 token 保存到 Keychain。
    func ensureAccount() async throws -> APIClient {
        if accessToken != nil {
            return makeClient()
        }

        isLoading = true
        defer { isLoading = false }
        let account = try await AccountService(client: makeClient()).createAccount()
        guard let token = account.accessToken, !token.isEmpty else {
            throw TelegraphError.missingToken
        }
        try tokenStore.saveString(token, for: TokenStore.Key.accessToken.rawValue)
        accessToken = token
        apply(account)
        return makeClient()
    }

    /// Compatibility alias for callers that use an authenticated-client name.
    func authenticatedClient() async throws -> APIClient {
        try await ensureAccount()
    }

    func updateAuthorProfile(name: String, url: String?) throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = url?.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            tokenStore.delete(Self.authorNameKey)
            authorName = nil
        } else {
            try tokenStore.saveString(trimmedName, for: Self.authorNameKey)
            authorName = trimmedName
        }

        if let trimmedURL, !trimmedURL.isEmpty {
            try tokenStore.saveString(trimmedURL, for: Self.authorURLKey)
            authorURL = trimmedURL
        } else {
            tokenStore.delete(Self.authorURLKey)
            authorURL = nil
        }
    }

    /// 撤销当前 token；成功后清除本地身份，下次发布会重新注册。
    func revokeAccess() async throws {
        if accessToken != nil {
            _ = try await makeClient().call(
                "revokeAccessToken",
                params: [:],
                as: TelegraphAccount.self
            )
        }
        clearLocalAccess()
    }

    private func clearLocalAccess() {
        tokenStore.delete(TokenStore.Key.accessToken.rawValue)
        tokenStore.delete(TokenStore.Key.shortName.rawValue)
        accessToken = nil
        shortName = nil
    }

    private func apply(_ account: TelegraphAccount) {
        if let shortName = account.shortName, !shortName.isEmpty {
            self.shortName = shortName
            try? tokenStore.saveString(shortName, for: TokenStore.Key.shortName.rawValue)
        }
        if let authorName = account.authorName {
            self.authorName = authorName
            try? tokenStore.saveString(authorName, for: Self.authorNameKey)
        }
        if let authorUrl = account.authorUrl {
            self.authorURL = authorUrl
            try? tokenStore.saveString(authorUrl, for: Self.authorURLKey)
        }
    }

    private enum MirrorFallback {
        static let apiBase = "https://api.telegra.ph"
    }
}
