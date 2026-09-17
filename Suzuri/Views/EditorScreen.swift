import SwiftUI

/// 发布界面（D1 验证链路，D4 装配视觉系统）。
///
/// 流程不变：输入标题/正文 → 发布 → 返回 telegra.ph URL 可拷贝。
/// 账号匿名注册，token 存 Keychain，重启仍在。
/// D4 仅改视觉：`AppBackground` 背景、发布栏玻璃容器 + `AppGlassButton`、
/// 大标题/作者胶囊样式；**不改 APIClient/Models/发布流程逻辑**。
struct EditorScreen: View {
    @State private var title: String = ""
    @State private var authorName: String = ""
    @State private var document = BlockEditorDocument()
    @State private var isPublishing: Bool = false
    @State private var publishedURL: URL?
    @State private var errorMessage: String?

    private let tokenStore = TokenStore()

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        // 标题：大标题无边框
                        TextField("无标题", text: $title)
                            .font(.largeTitle.weight(.bold))
                            .textInputAutocapitalization(.sentences)
                            .submitLabel(.next)

                        // 作者名胶囊
                        TextField("作者名（可选）", text: $authorName)
                            .font(.subheadline)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .appGlass(cornerRadius: 999)

                        Divider()
                            .opacity(0.4)

                        // 正文：块编辑器负责拆分、聚焦与块类型切换。
                        BlockEditorView()
                            .frame(minHeight: 240, maxHeight: 480)
                            .environment(document)

                        if let url = publishedURL {
                            AppGlassCard(cornerRadius: 20) {
                                HStack {
                                    Label("发布成功", systemImage: "checkmark.circle.fill")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Color.brand600)
                                    Spacer()
                                    ShareLink(item: url) {
                                        Image(systemName: "square.and.arrow.up")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(Color.brand600)
                                    }
                                    .accessibilityLabel("分享链接")
                                }
                                Text(url.absoluteString)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                    .padding(.top, 2)
                            }
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 120) // 给底部发布栏留位
                }
            }
            .navigationTitle("Suzuri")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                publishBar
            }
            .alert("发布失败", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .sensoryFeedback(.success, trigger: publishedURL)   // 发布成功触感反馈（iOS 17）
        }
    }

    /// 底部发布栏：草稿状态点 + 发布按钮，玻璃容器。
    private var publishBar: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(hasContent ? Color.brand600 : Color.secondary.opacity(0.4))
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)   // 装饰状态点，信息已由发布按钮表达

            AppGlassButton(
                title: "发布",
                systemImage: "paperplane.fill",
                style: .primary,
                isLoading: isPublishing
            ) {
                Task { await publish() }
            }
            .disabled(!canPublish)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .appGlass(cornerRadius: 24)
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    private var hasContent: Bool {
        let bodyHasContent = document.blocks.contains { block in
            if case .divider = block {
                return true
            }
            return !block.isEmpty
        }
        return !title.trimmingCharacters(in: .whitespaces).isEmpty || bodyHasContent
    }

    private var canPublish: Bool {
        // 恢复 D1 标题必填：空标题会触发 API 报错；正文可为空。
        !title.trimmingCharacters(in: .whitespaces).isEmpty && !isPublishing
    }

    /// 发布：取/建账号 → 构造 Node content → 校验 64KB → createPage。（D1 逻辑，未改）
    private func publish() async {
        await MainActor.run {
            isPublishing = true
            errorMessage = nil
        }
        defer {
            Task { @MainActor in isPublishing = false }
        }

        do {
            let blocks = document.blocks
            _ = try BlockEncoder.encodedData(for: blocks)
            let nodes = BlockEncoder.nodesForPublishing(blocks)
            let contentData: Data
            do {
                contentData = try JSONEncoder().encode(nodes)
            } catch {
                throw TelegraphError.invalidResponse
            }
            if contentData.count > BlockEncoder.maxContentBytes {
                throw TelegraphError.contentTooLarge(bytes: contentData.count)
            }

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

            // 2. 空段落过滤后保留完整块结构，并将其编码为 Telegraph Node。
            // 3. createPage：content 作为 JSON 字符串 query 参数。
            let contentJSON = String(data: contentData, encoding: .utf8) ?? "[]"
            let params: [String: String] = [
                "title": title,
                "author_name": authorName,
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
                withAnimation(AppAnimation.listInsert) {
                    publishedURL = url
                }
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