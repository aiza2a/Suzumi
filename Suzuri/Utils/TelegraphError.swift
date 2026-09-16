import Foundation

/// 全 App 统一错误类型。
enum TelegraphError: Error, Equatable {
    /// `ok == false`，服务器返回的 error 字符串。
    case api(message: String)
    /// 信封或 JSON 解析失败。
    case invalidResponse
    /// URLSession 层错误（含非 2xx HTTP）。
    case network(underlying: String)
    /// 发布内容超过 64KB 上限。
    case contentTooLarge(bytes: Int)
    /// 需要账号 token 但缺失。
    case missingToken
}