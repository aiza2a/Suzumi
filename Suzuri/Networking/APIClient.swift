import Foundation

/// Telegraph API 统一客户端。
///
/// 参考实现依据：
/// - token 注入方式对齐 `telegraph-android/AuthInterceptor.kt`：access_token 作为
///   query 参数追加（非 header）。
/// - 方法路径对齐 `telegraph-android/RestApi.kt` 的端点（createAccount/createPage 等）。
/// - 信封解析对齐 `dp5a/Telegraph` 的 `Response<T>` / `unwrapResponse`。
struct APIClient: Sendable {
    /// Telegraph API 根地址，默认 https://api.telegra.ph
    var baseURL: URL
    let session: URLSession
    /// 当前账号 token；非 nil 时自动追加为 `access_token` query 参数。
    var accessToken: String?

    /// 所有方法统一走此入口，参数均追加到 query（对齐 AuthInterceptor）。
    /// - parameters:
    ///   - method: Telegraph 方法名，如 "createAccount" / "createPage"。
    ///   - params: 业务参数（不含 access_token，由本方法注入）。
    ///   - type: 期望的 result 类型。
    ///   - httpMethod: 请求方法；读取接口使用 GET，写入接口默认 POST。
    /// - returns: 信封内 `result`。
    /// - throws: `TelegraphError`（api / invalidResponse / network）。
    func call<T: Decodable>(_ method: String,
                            params: [String: String],
                            as type: T.Type,
                            httpMethod: String = "POST") async throws -> T {
        var comps = URLComponents(url: baseURL.appendingPathComponent(method),
                                  resolvingAgainstBaseURL: false)!
        var items = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        if let t = accessToken {
            items.append(URLQueryItem(name: "access_token", value: t))
        }
        comps.queryItems = items

        var req = URLRequest(url: comps.url!)
        req.httpMethod = httpMethod

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw TelegraphError.network(underlying: error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw TelegraphError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw TelegraphError.network(underlying: "HTTP \(http.statusCode)")
        }

        let envelope: Envelope<T>
        do {
            envelope = try JSONDecoder().decode(Envelope<T>.self, from: data)
        } catch {
            throw TelegraphError.invalidResponse
        }

        guard envelope.ok, let result = envelope.result else {
            throw TelegraphError.api(message: envelope.error ?? "unknown")
        }
        return result
    }
}