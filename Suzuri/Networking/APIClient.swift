import Foundation

/// Telegraph API 统一客户端。
///
/// 参考实现依据：
/// - token 注入方式对齐 `telegraph-android/AuthInterceptor.kt`：access_token 作为 query 参数追加（非 header）。
/// - 方法路径对齐 `telegraph-android/RestApi.kt` 的端点（createAccount/createPage 等）。
/// - 信封解析对齐 `dp5a/Telegraph` 的 `Response<T>` / `unwrapResponse`。
struct APIClient: Sendable {
    /// Telegraph API 根地址，默认 https://api.telegra.ph
    var baseURL: URL
    let session: URLSession
    /// 当前账号 token；非 nil 时自动追加为 `access_token` query 参数。
    var accessToken: String?

    /// 所有方法统一走此入口。GET 参数进入 query，写入接口使用表单 body。
    /// token 仍作为 query 参数注入。
    func makeRequest(
        _ method: String,
        params: [String: String],
        httpMethod: String = "POST"
    ) throws -> URLRequest {
        guard var comps = URLComponents(
            url: baseURL.appendingPathComponent(method),
            resolvingAgainstBaseURL: false
        ) else {
            throw TelegraphError.invalidResponse
        }

        let normalizedMethod = httpMethod.uppercased()
        var queryItems = comps.queryItems ?? []
        if normalizedMethod == "GET" {
            queryItems.append(contentsOf: params
                .sorted { $0.key < $1.key }
                .map { URLQueryItem(name: $0.key, value: $0.value) })
        }
        if let token = accessToken {
            queryItems.append(URLQueryItem(name: "access_token", value: token))
        }
        comps.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = comps.url else {
            throw TelegraphError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = normalizedMethod

        if normalizedMethod != "GET" {
            request.setValue(
                "application/x-www-form-urlencoded; charset=utf-8",
                forHTTPHeaderField: "Content-Type"
            )
            request.httpBody = try formEncoded(params)
        }
        return request
    }

    /// 发送请求并解包 Telegraph envelope。
    func call<T: Decodable & Sendable>(
        _ method: String,
        params: [String: String],
        as type: T.Type,
        httpMethod: String = "POST"
    ) async throws -> T {
        let request = try makeRequest(method, params: params, httpMethod: httpMethod)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
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

        if envelope.ok {
            guard let result = envelope.result else {
                throw TelegraphError.invalidResponse
            }
            return result
        }

        guard let error = envelope.error, !error.isEmpty else {
            throw TelegraphError.invalidResponse
        }
        throw TelegraphError.api(message: error)
    }

    /// Encodes fields according to `application/x-www-form-urlencoded` rules.
    private func formEncoded(_ params: [String: String]) throws -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._*")

        let encoded = try params
            .sorted { $0.key < $1.key }
            .map { key, value in
                guard let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed),
                      let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed)
                else {
                    throw TelegraphError.invalidResponse
                }
                return "\(encodedKey.replacingOccurrences(of: "%20", with: "+"))="
                    + encodedValue.replacingOccurrences(of: "%20", with: "+")
            }
            .joined(separator: "&")
        return Data(encoded.utf8)
    }
}
