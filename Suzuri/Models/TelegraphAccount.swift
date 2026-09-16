import Foundation

/// Telegraph 账号。
///
/// 字段映射采用 snake_case 命名（telegraph API 约定）。
struct TelegraphAccount: Codable, Equatable {
    let shortName: String?
    let authorName: String?
    let authorUrl: String?
    let accessToken: String?
    let authUrl: String?
    let pageCount: Int?

    private enum CodingKeys: String, CodingKey {
        case shortName = "short_name"
        case authorName = "author_name"
        case authorUrl = "author_url"
        case accessToken = "access_token"
        case authUrl = "auth_url"
        case pageCount = "page_count"
    }
}