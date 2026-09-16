import Foundation

/// 图床上传协议。
protocol ImageHosting: Sendable {
    var id: String { get }
    var displayName: String { get }

    /// 上传图片数据，返回可直接写入 `img[src]` 的绝对 URL。
    func upload(_ data: Data, filename: String, mimeType: String) async throws -> URL
}

/// 图床上传错误。
enum HostError: Error, Equatable, Sendable {
    /// 服务端明确返回上传失败。
    case uploadFailed(String)
    /// 响应不是约定的 JSON 格式，或 URL 无法解析。
    case badResponse
    /// URLSession 或底层网络错误。
    case transport
}

/// 统一生成 multipart boundary。
func makeMultipartBoundary() -> String {
    "Boundary-\(UUID().uuidString)"
}

/// 统一 multipart/form-data 构造。字段名固定为 `file`。
func makeMultipartBody(data: Data, filename: String, mimeType: String,
                       boundary: String) -> Data {
    var body = Data()
    let separator = "--\(boundary)\r\n".data(using: .utf8)!
    let ending = "--\(boundary)--\r\n".data(using: .utf8)!

    body.append(separator)
    body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
    body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
    body.append(data)
    body.append("\r\n".data(using: .utf8)!)
    body.append(ending)
    return body
}

/// 判断 URL 是否为可直接用于图片节点的 HTTP(S) 地址。
func isHTTPURL(_ url: URL) -> Bool {
    guard let scheme = url.scheme?.lowercased(),
          scheme == "http" || scheme == "https",
          url.host != nil else {
        return false
    }
    return true
}
