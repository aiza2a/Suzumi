import Foundation

enum ExternalServiceLinkError: LocalizedError {
    case postimagesDirectLinkRequired
    case telegraphAuthorizationLinkRequired

    var errorDescription: String? {
        switch self {
        case .postimagesDirectLinkRequired:
            return "请粘贴 Postimages 的 Direct link 图片直链（https://i.postimg.cc/…），不要使用图片展示页或论坛代码。"
        case .telegraphAuthorizationLinkRequired:
            return "请从 Telegram 的 @telegraph 获取新的登录链接，格式为 https://edit.telegra.ph/auth/… 。链接只能使用一次，且会过期。"
        }
    }
}

enum PostimagesLink {
    static func validatedURL(_ input: String) throws -> URL {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value),
              url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "i.postimg.cc",
              url.user == nil, url.password == nil, url.port == nil,
              url.query == nil, url.fragment == nil,
              url.pathComponents.count >= 3,
              ["jpg", "jpeg", "png", "gif", "webp", "avif", "bmp", "tif", "tiff", "heic"].contains(url.pathExtension.lowercased()) else {
            throw ExternalServiceLinkError.postimagesDirectLinkRequired
        }
        return url
    }
}

enum TelegraphLoginLink {
    static func validatedURL(_ input: String) throws -> URL {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value),
              url.scheme?.lowercased() == "https",
              ["edit.telegra.ph", "telegra.ph"].contains(url.host?.lowercased() ?? ""),
              url.user == nil, url.password == nil, url.port == nil,
              url.query == nil, url.fragment == nil,
              url.path.range(of: "^/auth/[A-Za-z0-9_-]+$", options: .regularExpression) != nil else {
            throw ExternalServiceLinkError.telegraphAuthorizationLinkRequired
        }
        return url
    }

    static func tokenCandidates(from cookies: [HTTPCookie]) -> [String] {
        // Cookie names are not a public API. The official getAccountInfo response,
        // not a cookie name or its position, decides which value is an access token.
        let trusted = cookies.filter {
            let domain = $0.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return ["telegra.ph", "edit.telegra.ph"].contains(domain)
                && $0.isSecure
                && !$0.value.isEmpty
                && ($0.expiresDate.map { $0 > Date() } ?? true)
        }.sorted {
            if ($0.name == "tph_token") != ($1.name == "tph_token") { return $0.name == "tph_token" }
            return $0.name < $1.name
        }
        var seen = Set<String>()
        return trusted.compactMap { seen.insert($0.value).inserted ? $0.value : nil }
    }

    static func isInvalidTokenResponse(_ error: Error) -> Bool {
        guard case TelegraphError.api(let message) = error else { return false }
        return message.uppercased() == "ACCESS_TOKEN_INVALID"
    }
}
