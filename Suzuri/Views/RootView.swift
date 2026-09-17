import Foundation
import SwiftUI

/// 发布 Debug 界面（D1 验证链路用，D5 替换为正式界面）。
///
/// 流程：输入标题/正文与图片 → 发布 → 返回 telegra.ph URL 可拷贝。
/// 账号匿名注册，token 存 Keychain，重启仍在。
struct RootView: View {
    @State private var title: String = ""
    @State private var bodyText: String = ""
    @State private var blocks: [Block] = []
    @State private var isPublishing: Bool = false
    @State private var isUploadingImage: Bool = false
    @State private var publishedURL: URL?
    @State private var errorMessage: String?
    @State private var imageUploadErrorMessage: String?
    @State private var retryImageData: Data?
    @State private var imageProviderMessage: String?

    private let tokenStore = TokenStore()
    private let imagePipeline: ImagePipeline

    init(imagePipeline: ImagePipeline = ImagePipeline()) {
        self.imagePipeline = imagePipeline
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("文章") {
                    TextField("标题", text: $title)
                    TextField("正文（空行分段）", text: $bodyText, axis: .vertical)
                        .lineLimit(6...12)
                }

                Section("图片") {
                    PhotoPickerButton(
                        onImageData: { data in
                            Task { @MainActor in
                                await uploadImage(data)
                            }
                        },
                        onError: { error in
                            imageUploadErrorMessage = "读取图片失败：\(error.localizedDescription)"
                            retryImageData = nil
                        }
                    )
                    .disabled(isUploadingImage || isPublishing)

                    if isUploadingImage {
                        ProgressView("上传中…")
                    }
                    if let imageProviderMessage {
                        Text(imageProviderMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button {
                        Task { @MainActor in await publish() }
                    } label: {
                        if isPublishing {
                            ProgressView()
                        } else {
                            Text("发布")
                        }
                    }
                    .disabled(
                        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || isPublishing
                            || isUploadingImage
                    )
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
            .alert("图片上传失败", isPresented: Binding(
                get: { imageUploadErrorMessage != nil },
                set: { if !$0 { imageUploadErrorMessage = nil; retryImageData = nil } }
            )) {
                if retryImageData != nil {
                    Button("重试") {
                        if let data = retryImageData {
                            Task { @MainActor in await uploadImage(data) }
                        }
                    }
                }
                Button("取消", role: .cancel) {
                    imageUploadErrorMessage = nil
                    retryImageData = nil
                }
            } message: {
                Text(imageUploadErrorMessage ?? "")
            }
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

    /// 统一执行压缩、缓存与上传；成功后把图片块追加到待发布内容。
    @MainActor
    private func uploadImage(_ sourceData: Data) async {
        isUploadingImage = true
        imageUploadErrorMessage = nil
        retryImageData = nil
        defer { isUploadingImage = false }

        do {
            let result = try await imagePipeline.processAndUpload(sourceData)
            blocks.append(.figure(id: UUID(), imageURL: result.url, caption: ""))
            imageProviderMessage = "图片已上传（\(result.providerID)）"
        } catch {
            retryImageData = sourceData
            imageUploadErrorMessage = describeImageUploadError(error)
        }
    }

    /// 发布：取/建账号 → 统一编码段落与图片块 → createPage。
    @MainActor
    private func publish() async {
        isPublishing = true
        errorMessage = nil
        defer { isPublishing = false }

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

            // 2. 正文段落与已经上传成功的图片统一组成块列表。
            let paragraphs = bodyText
                .components(separatedBy: "\n\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map { Block.paragraph(id: UUID(), text: $0) }
            let contentBlocks = paragraphs + blocks
            let nodes = BlockEncoder.toNodes(contentBlocks)

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

            let page: TelegraphPage = try await client.call(
                "createPage",
                params: params,
                as: TelegraphPage.self
            )

            // 5. 成功 → 显示 URL 可拷贝；失败 → Alert 显示 error。
            guard let urlStr = page.url, let url = URL(string: urlStr) else {
                throw TelegraphError.invalidResponse
            }
            publishedURL = url
        } catch {
            errorMessage = (error as? TelegraphError).map(describe) ?? error.localizedDescription
        }
    }

    private func describeImageUploadError(_ error: Error) -> String {
        if let hostError = error as? HostError {
            switch hostError {
            case .uploadFailed(let message): return "图片上传失败：\(message)"
            case .badResponse: return "图片上传失败：响应解析失败"
            case .transport: return "图片上传失败：网络连接失败"
            }
        }
        if error is ImageCompressorError {
            return "图片上传失败：无法读取图片"
        }
        return "图片上传失败：\(error.localizedDescription)"
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
