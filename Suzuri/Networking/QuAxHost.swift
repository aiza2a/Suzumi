import Foundation

/// qu.ax 图床 Provider。
struct QuAxHost: ImageHosting {
    static let endpoint = URL(string: "https://qu.ax/upload.php")!

    let session: URLSession
    private let uploadEndpoint: URL

    var id: String { "quax" }
    var displayName: String { "qu.ax" }

    init(endpoint: URL = QuAxHost.endpoint, session: URLSession = .shared) {
        self.uploadEndpoint = endpoint
        self.session = session
    }

    func upload(_ data: Data, filename: String, mimeType: String) async throws -> URL {
        let boundary = makeMultipartBoundary()
        var request = URLRequest(url: uploadEndpoint)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)",
                         forHTTPHeaderField: "Content-Type")
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

            let result: Response
            do {
                result = try JSONDecoder().decode(Response.self, from: data)
            } catch {
                throw HostError.badResponse
            }

            guard result.success else {
                throw HostError.uploadFailed(result.message ?? result.error ?? "qu.ax upload failed")
            }
            guard let file = result.files.first else {
                throw HostError.uploadFailed("qu.ax returned no files")
            }
            guard let url = URL(string: file.url), isHTTPURL(url) else {
                throw HostError.badResponse
            }
            return url
        } catch let error as HostError {
            throw error
        } catch {
            throw HostError.transport
        }
    }

    private struct Response: Decodable {
        let success: Bool
        let files: [File]
        let error: String?
        let message: String?

        private enum CodingKeys: String, CodingKey {
            case success
            case files
            case error
            case message
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            success = try container.decode(Bool.self, forKey: .success)
            files = try container.decodeIfPresent([File].self, forKey: .files) ?? []
            error = try container.decodeIfPresent(String.self, forKey: .error)
            message = try container.decodeIfPresent(String.self, forKey: .message)
        }
    }

    private struct File: Decodable {
        let url: String
    }
}
