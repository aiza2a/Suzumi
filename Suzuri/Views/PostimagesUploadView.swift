import SwiftUI
import WebKit

/// Uses Postimages' own uploader, including its file picker and human verification.
/// Only a direct image URL is transferred back to the article.
struct PostimagesUploadView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var directLink = ""
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var reloadID = UUID()
    let onInsert: (URL) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("上传图片后，复制 Direct link 并粘贴到这里。")
                        .font(.subheadline).foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        TextField("https://i.postimg.cc/…", text: $directLink)
                            .keyboardType(.URL).textInputAutocapitalization(.never)
                            .autocorrectionDisabled().textFieldStyle(.roundedBorder)
                        Button("插入", action: insert)
                            .buttonStyle(.borderedProminent)
                            .disabled(directLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    if let errorMessage {
                        Text(errorMessage).font(.caption).foregroundStyle(.red)
                    }
                }
                .padding()
                Divider()
                if isLoading { ProgressView().padding(8) }
                PostimagesBrowser(onError: { errorMessage = $0 }, onLoading: { isLoading = $0 })
                    .id(reloadID)
            }
            .navigationTitle("Postimages 图床")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        errorMessage = nil
                        isLoading = true
                        reloadID = UUID()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("重新加载 Postimages")
                }
            }
        }
    }

    private func insert() {
        do {
            let url = try PostimagesLink.validatedURL(directLink)
            onInsert(url)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct PostimagesBrowser: UIViewRepresentable {
    let onError: (String) -> Void
    let onLoading: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onError: onError, onLoading: onLoading) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.load(URLRequest(url: URL(string: "https://postimages.org/")!))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let onError: (String) -> Void
        let onLoading: (Bool) -> Void
        init(onError: @escaping (String) -> Void, onLoading: @escaping (Bool) -> Void) {
            self.onError = onError
            self.onLoading = onLoading
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            onLoading(true)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onLoading(false)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard navigationAction.targetFrame?.isMainFrame != false else {
                decisionHandler(.allow)
                return
            }
            decisionHandler(isTrusted(navigationAction.request.url) ? .allow : .cancel)
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            // Postimages opens individual results in target=_blank; keep those in this sheet.
            if navigationAction.targetFrame == nil, isTrusted(navigationAction.request.url) {
                webView.load(navigationAction.request)
            }
            return nil
        }

        private func isTrusted(_ url: URL?) -> Bool {
            let hosts = ["postimages.org", "www.postimages.org", "postimg.cc", "www.postimg.cc", "i.postimg.cc"]
            return url?.scheme == "https" && hosts.contains(url?.host?.lowercased() ?? "")
                && url?.user == nil && url?.password == nil && url?.port == nil
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            report(error)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            report(error)
        }

        private func report(_ error: Error) {
            guard (error as NSError).code != NSURLErrorCancelled else { return }
            onLoading(false)
            onError("Postimages 无法加载：\(error.localizedDescription)")
        }
    }
}
