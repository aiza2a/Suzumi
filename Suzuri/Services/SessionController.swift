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
    @ObservationIgnored
    private var activeOrigin: String
    @ObservationIgnored
    private var accountTask: Task<APIClient, Error>?

    private(set) var accessToken: String?
    private(set) var shortName: String?
    private(set) var authorName: String?
    private(set) var authorURL: String?
    private(set) var isLoading = false
    private(set) var isLoaded = false
    private(set) var loadError: TelegraphError?

    var isAnonymous: Bool { accessToken == nil }

    /// Current API origin, excluding path/query so credentials are isolated by host.
    var currentOrigin: String {
        TokenStore.origin(for: serverManager.apiBase)
    }

    /// Stable local scope for the active account; anonymous drafts use a fixed scope.
    var accountFingerprint: String {
        TokenStore.fingerprint(accessToken ?? "anonymous")
    }

    init(
        serverManager: ServerManager = ServerManager(),
        tokenStore: TokenStore = TokenStore(),
        session: URLSession = .shared
    ) {
        self.serverManager = serverManager
        self.tokenStore = tokenStore
        self.session = session

        let origin = TokenStore.origin(for: serverManager.apiBase)
        self.activeOrigin = origin
        self.accessToken = tokenStore.loadString(.accessToken, origin: origin)
        self.shortName = tokenStore.loadString(.shortName, origin: origin)
        self.authorName = tokenStore.loadString(Self.authorNameKey)
        self.authorURL = tokenStore.loadString(Self.authorURLKey)
    }

    /// 加载本地 token，并尽力校验账号；临时失败保留重试机会。
    func load() async {
        synchronizeOrigin()
        guard !isLoaded else { return }

        isLoading = true
        loadError = nil
        defer { isLoading = false }

        guard accessToken != nil else {
            isLoaded = true
            return
        }

        do {
            let client = try validatedClient()
            let account = try await AccountService(client: client).getAccountInfo()
            guard currentOrigin == activeOrigin else { return }
            apply(account, origin: activeOrigin)
            isLoaded = true
        } catch {
            let normalized = normalize(error)
            loadError = normalized
            let authenticationFailed = handleAuthenticationFailure(normalized)
            if authenticationFailed || accessToken == nil || !isTransientLoadError(normalized) {
                // Invalid credentials become anonymous mode; permanent API errors should not
                // cause an endless launch loop. Network/decoding errors remain retryable.
                isLoaded = true
            } else {
                isLoaded = false
            }
        }
    }

    /// 返回当前 APIClient；没有 token 时仍可读取公开页面。
    func makeClient() -> APIClient {
        synchronizeOrigin()
        return makeClientWithoutSynchronization()
    }

    /// Fails instead of silently routing an invalid custom mirror to Telegraph.
    func validatedClient() throws -> APIClient {
        synchronizeOrigin()
        if let error = serverManager.configurationError {
            throw error
        }
        return makeClientWithoutSynchronization()
    }

    /// Returns a client for an arbitrary mirror with that mirror's own token.
    func makeClient(serverManager: ServerManager) -> APIClient {
        let baseURL = serverManager.apiURL ?? URL(string: MirrorFallback.apiBase)!
        let origin = TokenStore.origin(for: serverManager.apiBase)
        let token = tokenStore.loadString(.accessToken, origin: origin)
        return APIClient(baseURL: baseURL, session: session, accessToken: token)
    }

    /// 首次发布时才创建匿名账号；并发调用共享同一个注册任务。
    func ensureAccount() async throws -> APIClient {
        synchronizeOrigin()
        if let accountTask {
            return try await accountTask.value
        }
        if accessToken != nil {
            return try validatedClient()
        }

        let origin = activeOrigin
        let registrationClient = try validatedClient()
        let task = Task { @MainActor [weak self] () throws -> APIClient in
            guard let self else {
                throw TelegraphError.network(underlying: "session deallocated")
            }

            let account = try await AccountService(client: registrationClient).createAccount()
            guard self.activeOrigin == origin,
                  self.currentOrigin == origin else {
                throw TelegraphError.network(underlying: "server configuration changed")
            }
            guard let token = account.accessToken, !token.isEmpty else {
                throw TelegraphError.missingToken
            }

            try self.tokenStore.saveString(token, for: .accessToken, origin: origin)
            self.accessToken = token
            self.apply(account, origin: origin)
            self.isLoaded = true
            return self.makeClientWithoutSynchronization()
        }
        accountTask = task

        do {
            let client = try await task.value
            accountTask = nil
            return client
        } catch {
            accountTask = nil
            throw error
        }
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
            do {
                _ = try await validatedClient().call(
                    "revokeAccessToken",
                    params: [:],
                    as: TelegraphAccount.self
                )
            } catch {
                handleAuthenticationFailure(error)
                throw error
            }
        }
        clearLocalAccess()
    }

    /// Clears credentials after an explicit authentication failure.
    @discardableResult
    func handleAuthenticationFailure(_ error: Error) -> Bool {
        let normalized = normalize(error)
        let isAuthenticationFailure: Bool
        switch normalized {
        case .api(let message):
            isAuthenticationFailure = message.uppercased().contains("ACCESS_TOKEN")
        case .network(let detail):
            isAuthenticationFailure = detail.contains("HTTP 401") || detail.contains("HTTP 403")
        default:
            isAuthenticationFailure = false
        }

        if isAuthenticationFailure {
            clearLocalAccess()
            isLoaded = true
        }
        return isAuthenticationFailure
    }

    /// Reloads credentials whenever the user switches API mirrors.
    func synchronizeOrigin() {
        let origin = currentOrigin
        guard origin != activeOrigin else { return }

        accountTask?.cancel()
        accountTask = nil
        activeOrigin = origin
        accessToken = tokenStore.loadString(.accessToken, origin: origin)
        shortName = tokenStore.loadString(.shortName, origin: origin)
        isLoaded = false
        loadError = nil
    }

    private func makeClientWithoutSynchronization() -> APIClient {
        let baseURL = serverManager.apiURL ?? URL(string: MirrorFallback.apiBase)!
        return APIClient(baseURL: baseURL, session: session, accessToken: accessToken)
    }

    private func apply(_ account: TelegraphAccount, origin: String) {
        if let shortName = account.shortName, !shortName.isEmpty {
            self.shortName = shortName
            try? tokenStore.saveString(shortName, for: .shortName, origin: origin)
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

    private func clearLocalAccess() {
        tokenStore.delete(.accessToken, origin: activeOrigin)
        tokenStore.delete(.shortName, origin: activeOrigin)
        accessToken = nil
        shortName = nil
    }

    private func normalize(_ error: Error) -> TelegraphError {
        if let error = error as? TelegraphError {
            return error
        }
        return .network(underlying: error.localizedDescription)
    }

    private func isTransientLoadError(_ error: TelegraphError) -> Bool {
        switch error {
        case .network, .invalidResponse:
            true
        case .api, .contentTooLarge, .missingToken:
            false
        }
    }

    private enum MirrorFallback {
        static let apiBase = "https://api.telegra.ph"
    }
}
