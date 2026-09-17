import Foundation

/// 匿名账号服务：封装 createAccount / getAccountInfo。
struct AccountService: Sendable {
    let client: APIClient

    /// 匿名注册。
    /// shortName 自动生成 "user_<8位十六进制>"（每 IP 约 2 个上限，勿滥用）。
    func createAccount() async throws -> TelegraphAccount {
        // UUID 前 8 位天然是十六进制；lowercased 仅为统一大小写。
        let name = "user_" + String(UUID().uuidString.prefix(8)).lowercased()
        return try await client.call("createAccount",
            params: ["short_name": name], as: TelegraphAccount.self)
    }

    /// 查询当前账号信息（依赖 client.accessToken）。
    func getAccountInfo() async throws -> TelegraphAccount {
        try await client.call(
            "getAccountInfo",
            params: ["fields": #"["short_name","author_name","author_url","page_count"]"#],
            as: TelegraphAccount.self,
            httpMethod: "GET"
        )
    }
}