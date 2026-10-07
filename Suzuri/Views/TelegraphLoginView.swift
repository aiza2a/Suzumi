import SwiftUI
import WebKit

struct TelegraphLoginView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var authorizationLink = ""
    @State private var accessToken = ""
    @State private var loginURL: URL?
    @State private var attemptID = UUID()
    @State private var errorMessage: String?
    @State private var isImporting = false
    @State private var importTask: Task<Void, Never>?
    let onToken: (String) async throws -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Label("连接已有的 Telegraph 账号", systemImage: "person.crop.circle.badge.checkmark")
                    .font(.title3.weight(.semibold))
                Text("在 Telegram 中打开 @telegraph，选择你要使用的账号，复制它提供的登录链接。回到这里粘贴，即可同步该账号的文章。")
                    .font(.subheadline).foregroundStyle(.secondary)
                Link(destination: URL(string: "https://t.me/telegraph")!) {
                    Label("打开 Telegram 的 @telegraph", systemImage: "paperplane")
                }
                .buttonStyle(.bordered)
                TextField("粘贴 Telegraph 登录链接", text: $authorizationLink)
                    .keyboardType(.URL).textInputAutocapitalization(.never)
                    .autocorrectionDisabled().textFieldStyle(.roundedBorder)
                    .privacySensitive()
                Button(action: beginLogin) {
                    HStack {
                        if isImporting { ProgressView() }
                        Text(isImporting ? "正在验证账号…" : "连接账号")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(authorizationLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isImporting)
                DisclosureGroup("已有 API access token") {
                    SecureField("粘贴 access token", text: $accessToken)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .privacySensitive()
                    Button("验证并导入") { importCandidates([accessToken]) }
                        .disabled(accessToken.isEmpty || isImporting)
                }
                .font(.subheadline)
                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red)
                }
                if let loginURL {
                    TelegraphAuthorizationBrowser(
                        url: loginURL,
                        onCandidates: importCandidates,
                        onError: { errorMessage = $0 }
                    )
                    .id(attemptID)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    Spacer()
                    Text("登录链接属于账号凭据，请勿分享给他人。Suzuri 仅在 Telegraph 官方站点完成登录，并将验证后的访问令牌保存在系统钥匙串中。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .navigationTitle("Telegram 授权")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { importTask?.cancel(); dismiss() }
                }
            }
            .interactiveDismissDisabled(isImporting)
            .onDisappear { importTask?.cancel() }
        }
    }

    private func beginLogin() {
        do {
            let url = try TelegraphLoginLink.validatedURL(authorizationLink)
            errorMessage = nil
            attemptID = UUID()
            loginURL = url
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func importCandidates(_ candidates: [String]) {
        guard !isImporting else { return }
        isImporting = true
        errorMessage = nil
        importTask = Task { @MainActor in
            do {
                for token in candidates {
                    try Task.checkCancellation()
                    do {
                        try await onToken(token)
                        try Task.checkCancellation()
                        dismiss()
                        isImporting = false
                        return
                    } catch {
                        // Only a definitive API rejection permits trying another cookie.
                        // Network, storage, cancellation and origin changes must surface.
                        guard TelegraphLoginLink.isInvalidTokenResponse(error) else { throw error }
                    }
                }
                errorMessage = "此登录会话未提供可用的 Telegraph API 凭据。请获取新的链接重试，或使用 access token 导入。"
            } catch is CancellationError {
                // User explicitly cancelled this attempt.
            } catch {
                errorMessage = "账号连接失败：\(error.localizedDescription)"
            }
            isImporting = false
        }
    }
}

private struct TelegraphAuthorizationBrowser: UIViewRepresentable {
    let url: URL
    let onCandidates: ([String]) -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCandidates: onCandidates, onError: onError) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // Every attempt starts empty, so a failed link cannot import a prior account.
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onCandidates: ([String]) -> Void
        let onError: (String) -> Void
        private var deliveredToken = false

        init(onCandidates: @escaping ([String]) -> Void, onError: @escaping (String) -> Void) {
            self.onCandidates = onCandidates
            self.onError = onError
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url,
                  url.scheme == "https",
                  ["telegra.ph", "edit.telegra.ph"].contains(url.host?.lowercased() ?? ""),
                  url.user == nil, url.password == nil, url.port == nil else {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !deliveredToken else { return }
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self, !self.deliveredToken else { return }
                let candidates = TelegraphLoginLink.tokenCandidates(from: cookies)
                guard !candidates.isEmpty else {
                    self.onError("没有取得 Telegraph 登录凭据。链接可能已过期或已使用，请在 @telegraph 获取新链接后重试。")
                    return
                }
                self.deliveredToken = true
                self.onCandidates(candidates)
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            report(error)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            report(error)
        }

        private func report(_ error: Error) {
            guard (error as NSError).code != NSURLErrorCancelled else { return }
            onError("Telegraph 登录页无法加载，请检查网络后重试。")
        }
    }
}
