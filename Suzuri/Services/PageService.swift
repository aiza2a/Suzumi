import Foundation

/// Telegraph 页面接口。
struct PageService: Sendable {
    let client: APIClient

    /// 分页读取当前账号的页面。
    func getPageList(offset: Int, limit: Int = 50) async throws -> (total: Int, pages: [Page]) {
        let result = try await client.call(
            "getPageList",
            params: [
                "offset": String(max(0, offset)),
                "limit": String(max(1, limit))
            ],
            as: PageList.self,
            httpMethod: "GET"
        )
        return (total: result.totalCount, pages: result.pages)
    }

    /// 读取单页；默认请求完整 Node 内容。
    func getPage(path: String, returnContent: Bool = true) async throws -> Page {
        try await client.call(
            "getPage/\(path)",
            params: ["return_content": returnContent ? "true" : "false"],
            as: Page.self,
            httpMethod: "GET"
        )
    }

    /// 编辑已有页面。
    func editPage(
        path: String,
        title: String,
        authorName: String?,
        authorUrl: String?,
        content: [TelegraphNode]
    ) async throws -> Page {
        let contentData = try encodedContent(content)
        return try await client.call(
            "editPage/\(path)",
            params: parameters(
                title: title,
                authorName: authorName,
                authorUrl: authorUrl,
                contentData: contentData
            ),
            as: Page.self
        )
    }

    /// 创建新页面。
    func createPage(
        title: String,
        authorName: String?,
        authorUrl: String?,
        content: [TelegraphNode]
    ) async throws -> Page {
        let contentData = try encodedContent(content)
        return try await client.call(
            "createPage",
            params: parameters(
                title: title,
                authorName: authorName,
                authorUrl: authorUrl,
                contentData: contentData
            ),
            as: Page.self
        )
    }

    /// Block 编辑器的便捷入口，编码仍由 BlockEncoder 统一执行。
    func editPage(
        path: String,
        title: String,
        authorName: String?,
        authorUrl: String?,
        blocks: [Block]
    ) async throws -> Page {
        let contentData = try BlockEncoder.encodedData(for: blocks)
        return try await client.call(
            "editPage/\(path)",
            params: parameters(
                title: title,
                authorName: authorName,
                authorUrl: authorUrl,
                contentData: contentData
            ),
            as: Page.self
        )
    }

    /// Block 编辑器的便捷入口，编码仍由 BlockEncoder 统一执行。
    func createPage(
        title: String,
        authorName: String?,
        authorUrl: String?,
        blocks: [Block]
    ) async throws -> Page {
        let contentData = try BlockEncoder.encodedData(for: blocks)
        return try await client.call(
            "createPage",
            params: parameters(
                title: title,
                authorName: authorName,
                authorUrl: authorUrl,
                contentData: contentData
            ),
            as: Page.self
        )
    }

    private func encodedContent(_ content: [TelegraphNode]) throws -> Data {
        let data: Data
        do {
            data = try JSONEncoder().encode(content)
        } catch {
            throw TelegraphError.invalidResponse
        }
        guard data.count <= BlockEncoder.maxContentBytes else {
            throw TelegraphError.contentTooLarge(bytes: data.count)
        }
        return data
    }

    private func parameters(
        title: String,
        authorName: String?,
        authorUrl: String?,
        contentData: Data
    ) -> [String: String] {
        [
            "title": title,
            "author_name": authorName ?? "",
            "author_url": authorUrl ?? "",
            "content": String(data: contentData, encoding: .utf8) ?? "[]",
            "return_content": "true"
        ]
    }
}
