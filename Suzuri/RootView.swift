import SwiftUI

/// 发布 Debug 界面（D1 验证链路用，D5 替换为正式界面）。
///
/// 流程：输入标题/正文 → 发布 → 返回 telegra.ph URL 可拷贝。
/// 账号匿名注册，token 存 Keychain，重启仍在。
struct RootView: View {
    @State private var title: String = ""
    @State private var bodyText: String = ""
    @State private var isPublishing: Bool = false
    @State private var publishedURL: URL?
    @State private var errorMessage: String?

    private let tokenStore = TokenStore()

    var body: some View {
        NavigationStack {
            Form {
                Section("文章") {
                    TextField("标题", text: $title)
                    TextField("正文（空行分段）", text: $bodyText, axis: .vertical)
                        .lineLimit(6...12)
                }

                Section {
                    Button {
                        Task { await publish() }
                    } label: {
                        if isPublishing {
                            ProgressView()
                        } else {
                            Text("发布")
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isPublishing)
                }

                if let url = publishedURL {
                    Section("发布成功") {
                        Text(url.absoluteString)
                            .font(.footnote)
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("Suzuri")
            .alert("发布失败", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    /// 发布：取/建账号 → 构造 Node content → 校验 64KB → createPage。
    private func publish() async {
        await MainActor.run {
            isPublishing = true
            errorMessage = nil
        }
        defer {
            Task { @MainActor in isPublishing = false }
        }

        do {
            let baseURL = URL(string: "https://api.telegra.ph")!
            var client = APIClient(baseURL: baseURL, session: .shared, accessToken: nil)

            // 1. 账号：Keychain 已有 token 则复用；否则匿名注册并持久化。
            let tokenKey = TokenStore.Key.accessToken.rawValue
            if let token = tokenStore.loadString(tokenKey) {
                client.accessToken = token
            } else {
                let account = try await AccountService(client: client).createAccount()
                guard let token = account.accessToken else {
                    throw TelegraphError.missingToken
                }
                try tokenStore.saveString(token, for: tokenKey)
                if let sn = account.shortName {
                    try? tokenStore.saveString(sn, for: TokenStore.Key.shortName.rawValue)
                }
                client.accessToken = token
            }

            // 2. 正文按空行拆为多个 <p> 段落；段落 trim 空则跳过。
            let paragraphs = bodyText
                .components(separatedBy: "\n\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            let nodes: [TelegraphNode] = paragraphs.map { para in
                TelegraphNode(tag: "p", attrs: nil, children: [.text(para)])
            }

            // 3. JSONEncoder 序列化 → 字节数 > 65536 抛 .contentTooLarge。
            let contentData: Data
            do {
                contentData = try JSONEncoder().encode(nodes)
            } catch {
                throw TelegraphError.invalidResponse
            }
            if contentData.count > 65_536 {
                throw TelegraphError.contentTooLarge(bytes: contentData.count)
            }

            // 4. createPage：content 作为 JSON 字符串 query 参数。
            let contentJSON = String(data: contentData, encoding: .utf8) ?? "[]"
            let params: [String: String] = [
                "title": title,
                "author_name": "",
                "content": contentJSON,
                "return_content": "false"
            ]

            let page: TelegraphPage = try await client.call("createPage",
                params: params, as: TelegraphPage.self)

            // 5. 成功 → 显示 URL 可拷贝；失败 → Alert 显示 error。
            guard let urlStr = page.url, let url = URL(string: urlStr) else {
                throw TelegraphError.invalidResponse
            }
            await MainActor.run {
                publishedURL = url
            }
        } catch {
            let msg = (error as? TelegraphError).map(describe) ?? error.localizedDescription
            await MainActor.run {
                errorMessage = msg
            }
        }
    }

    private func describe(_ error: TelegraphError) -> String {
        switch error {
        case .api(let m): return "API: \(m)"
        case .invalidResponse: return "响应解析失败"
        case .network(let u): return "网络: \(u)"
        case .contentTooLarge(let b): return "内容过大 (\(b) bytes > 64KB)"
        case .missingToken: return "缺少账号 token"
        }
    }
}

/// Telegraph Page（仅取 D1 所需字段：url）。
struct TelegraphPage: Decodable, Equatable {
    let url: String?
}