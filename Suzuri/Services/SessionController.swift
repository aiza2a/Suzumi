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
    @ObservationIgnored
    private var accountTaskID: UUID?
    @ObservationIgnored
    private var credentialGeneration = UUID()

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

        let defaultOrigin = TokenStore.origin(for: MirrorFallback.apiBase)
        Self.migrateLegacyCredentials(tokenStore: tokenStore, defaultOrigin: defaultOrigin)

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

        let requestOrigin = activeOrigin
        let requestToken = accessToken
        let requestGeneration = credentialGeneration
        do {
            let client = try validatedClient()
            let account = try await AccountService(client: client).getAccountInfo()
            guard requestOrigin == activeOrigin,
                  requestOrigin == currentOrigin,
                  requestGeneration == credentialGeneration,
                  requestToken == accessToken
            else { return }
            try apply(account, origin: requestOrigin)
            isLoaded = true
        } catch {
            guard requestOrigin == activeOrigin,
                  requestOrigin == currentOrigin,
                  requestGeneration == credentialGeneration,
                  requestToken == accessToken
            else { return }
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
        let generation = credentialGeneration
        let registrationClient = try validatedClient()
        let taskID = UUID()
        let task = Task { @MainActor [weak self] () throws -> APIClient in
            guard let self else {
                throw TelegraphError.network(underlying: "session deallocated")
            }

            let account = try await AccountService(client: registrationClient).createAccount()
            guard self.activeOrigin == origin,
                  self.currentOrigin == origin,
                  self.credentialGeneration == generation,
                  !Task.isCancelled else {
                throw TelegraphError.network(underlying: "server configuration changed")
            }
            guard let token = account.accessToken, !token.isEmpty else {
                throw TelegraphError.missingToken
            }

            try self.apply(account, origin: origin)
            try self.tokenStore.saveString(token, for: .accessToken, origin: origin)
            self.accessToken = token
            self.credentialGeneration = UUID()
            self.isLoaded = true
            return self.makeClientWithoutSynchronization()
        }
        accountTaskID = taskID
        accountTask = task

        do {
            let client = try await task.value
            if accountTaskID == taskID {
                accountTask = nil
                accountTaskID = nil
            }
            return client
        } catch {
            if accountTaskID == taskID {
                accountTask = nil
                accountTaskID = nil
            }
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
            try tokenStore.saveString("", for: Self.authorNameKey)
            authorName = nil
        } else {
            try tokenStore.saveString(trimmedName, for: Self.authorNameKey)
            authorName = trimmedName
        }

        if let trimmedURL, !trimmedURL.isEmpty {
            try tokenStore.saveString(trimmedURL, for: Self.authorURLKey)
            authorURL = trimmedURL
        } else {
            try tokenStore.saveString("", for: Self.authorURLKey)
            authorURL = nil
        }
    }

    /// 撤销当前 token；成功后清除本地身份，下次发布会重新注册。
    func revokeAccess() async throws {
        synchronizeOrigin()
        let origin = activeOrigin
        let token = accessToken
        let generation = credentialGeneration
        if accessToken != nil {
            do {
                _ = try await validatedClient().call(
                    "revokeAccessToken",
                    params: [:],
                    as: TelegraphAccount.self
                )
            } catch {
                if isCurrentRequest(origin: origin, token: token, generation: generation) {
                    handleAuthenticationFailure(error)
                }
                throw error
            }
        }
        guard isCurrentRequest(origin: origin, token: token, generation: generation) else { return }
        clearLocalAccess()
    }

    /// Import an existing API token; a Telegram login URL is not an API credential.
    /// Validation is sent only to the explicitly selected HTTPS API origin.
    func importAccessToken(_ value: String) async throws {
        synchronizeOrigin()
        let token = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, token.utf8.count <= 512,
              token.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || "_-".unicodeScalars.contains($0) })
        else { throw TelegraphError.api(message: "请输入有效的 Telegraph access_token，不要粘贴登录链接。") }
        if let error = serverManager.configurationError { throw error }
        guard let baseURL = serverManager.apiURL, baseURL.scheme?.lowercased() == "https" else {
            throw TelegraphError.api(message: "导入账号需要 HTTPS API 地址。")
        }
        accountTask?.cancel()
        accountTask = nil
        accountTaskID = nil
        credentialGeneration = UUID()
        let generation = credentialGeneration
        let origin = activeOrigin
        let previousToken = accessToken
        let client = APIClient(baseURL: baseURL, session: session, accessToken: token)
        let account = try await AccountService(client: client).getAccountInfo()
        guard isCurrentRequest(origin: origin, token: previousToken, generation: generation), !Task.isCancelled else {
            throw TelegraphError.api(message: "账号或服务器已改变，请重新导入。")
        }
        try apply(account, origin: origin)
        try tokenStore.saveString(token, for: .accessToken, origin: origin)
        accessToken = token
        credentialGeneration = UUID()
        isLoaded = true
        loadError = nil
    }

    private func isCurrentRequest(origin: String, token: String?, generation: UUID) -> Bool {
        origin == activeOrigin && origin == currentOrigin && token == accessToken && generation == credentialGeneration
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
        accountTaskID = nil
        activeOrigin = origin
        credentialGeneration = UUID()
        accessToken = tokenStore.loadString(.accessToken, origin: origin)
        shortName = tokenStore.loadString(.shortName, origin: origin)
        authorName = tokenStore.loadString(Self.authorNameKey)
        authorURL = tokenStore.loadString(Self.authorURLKey)
        isLoaded = false
        loadError = nil
    }

    private func makeClientWithoutSynchronization() -> APIClient {
        let baseURL = serverManager.apiURL ?? URL(string: MirrorFallback.apiBase)!
        return APIClient(baseURL: baseURL, session: session, accessToken: accessToken)
    }

    private func apply(_ account: TelegraphAccount, origin: String) throws {
        if let shortName = account.shortName, !shortName.isEmpty {
            try tokenStore.saveString(shortName, for: .shortName, origin: origin)
            self.shortName = shortName
        }
        if tokenStore.loadString(Self.authorNameKey) == nil, let authorName = account.authorName {
            self.authorName = authorName
        }
        if tokenStore.loadString(Self.authorURLKey) == nil, let authorUrl = account.authorUrl {
            self.authorURL = authorUrl
        }
    }

    private func clearLocalAccess() {
        credentialGeneration = UUID()
        accountTask?.cancel()
        accountTask = nil
        accountTaskID = nil
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

    private static func migrateLegacyCredentials(
        tokenStore: TokenStore,
        defaultOrigin: String
    ) {
        migrateLegacy(
            key: .accessToken,
            tokenStore: tokenStore,
            defaultOrigin: defaultOrigin
        )
        migrateLegacy(
            key: .shortName,
            tokenStore: tokenStore,
            defaultOrigin: defaultOrigin
        )
    }

    private static func migrateLegacy(
        key: TokenStore.Key,
        tokenStore: TokenStore,
        defaultOrigin: String
    ) {
        let legacyAccount = key.rawValue
        guard let legacyValue = tokenStore.loadString(legacyAccount) else { return }
        if tokenStore.loadString(key, origin: defaultOrigin) == nil {
            do {
                try tokenStore.saveString(legacyValue, for: key, origin: defaultOrigin)
            } catch {
                return
            }
        }
        tokenStore.delete(legacyAccount)
    }

    private enum MirrorFallback {
        static let apiBase = "https://api.telegra.ph"
    }
}
