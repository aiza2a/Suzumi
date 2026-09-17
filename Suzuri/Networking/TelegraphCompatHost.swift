import Foundation

/// 兼容 Telegraph 官方 `/upload` 协议的图床 Provider。
struct TelegraphCompatHost: ImageHosting {
    static let defaultBaseURL = URL(string: "https://telegraph-image.pages.dev")!

    var baseURL: URL
    var basicAuth: (user: String, pass: String)?
    let session: URLSession

    var id: String { "telegraph" }
    var displayName: String { "Telegraph 兼容图床" }

    init(baseURL: URL = TelegraphCompatHost.defaultBaseURL,
         basicAuth: (user: String, pass: String)? = nil,
         session: URLSession = .shared) {
        self.baseURL = baseURL
        self.basicAuth = basicAuth
        self.session = session
    }

    func upload(_ data: Data, filename: String, mimeType: String) async throws -> URL {
        let boundary = makeMultipartBoundary()
        var request = URLRequest(url: baseURL.appendingPathComponent("upload"))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)",
                         forHTTPHeaderField: "Content-Type")
        if let basicAuth {
            let credentials = "\(basicAuth.user):\(basicAuth.pass)"
            let encodedCredentials = Data(credentials.utf8).base64EncodedString()
            request.setValue("Basic \(encodedCredentials)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = makeMultipartBody(data: data, filename: filename,
                                              mimeType: mimeType, boundary: boundary)

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw HostError.badResponse
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw HostError.uploadFailed("HTTP \(httpResponse.statusCode)")
            }

            let result: [ImageData]
            do {
                result = try JSONDecoder().decode([ImageData].self, from: data)
            } catch {
                throw HostError.badResponse
            }
            guard let source = result.first?.src,
                  let url = resolvedURL(for: source) else {
                throw HostError.badResponse
            }
            return url
        } catch let error as HostError {
            throw error
        } catch {
            throw HostError.transport
        }
    }

    private func resolvedURL(for source: String) -> URL? {
        if source.lowercased().hasPrefix("http"),
           let url = URL(string: source),
           isHTTPURL(url) {
            return url
        }

        // Do not allow a network-path reference (`//host/path`) to replace the
        // configured host while resolving a supposedly relative response.
        guard source.hasPrefix("/"), !source.hasPrefix("//"),
              let url = URL(string: source, relativeTo: baseURL)?.absoluteURL,
              isHTTPURL(url) else {
            return nil
        }
        return url
    }

    private struct ImageData: Decodable {
        let src: String
    }
}
