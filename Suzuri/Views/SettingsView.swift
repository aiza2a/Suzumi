import SwiftUI

/// 设置页：账号、图床、服务器和关于四组配置。
@MainActor
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var sessionController: SessionController
    @State private var serverManager: ServerManager
    var showsDoneButton: Bool = false

    @AppStorage(ImageHostConfiguration.providerKey)
    private var imageProviderRaw = ImageProvider.quax.rawValue
    @AppStorage(ImageHostConfiguration.baseURLKey)
    private var imageBaseURL = TelegraphCompatHost.defaultBaseURL.absoluteString
    @AppStorage(ImageHostConfiguration.usernameKey)
    private var imageUsername = ""
    @AppStorage(ImageHostConfiguration.basicAuthKey)
    private var imageBasicAuthEnabled = false

    @State private var imagePassword: String
    @State private var authorName: String
    @State private var authorURL: String
    @State private var isShowingRevokeConfirmation = false
    @State private var errorMessage: String?
    @State private var statusMessage: String?

    private let tokenStore: TokenStore

    init(sessionController: SessionController, showsDoneButton: Bool = false) {
        self.tokenStore = TokenStore()
        self._sessionController = State(initialValue: sessionController)
        self._serverManager = State(initialValue: sessionController.serverManager)
        self.showsDoneButton = showsDoneButton
        self._authorName = State(initialValue: sessionController.authorName ?? "")
        self._authorURL = State(initialValue: sessionController.authorURL ?? "")
        self._imagePassword = State(
            initialValue: TokenStore().loadString(ImageHostConfiguration.passwordKey) ?? ""
        )
    }

    @MainActor
    init() {
        self.init(sessionController: SessionController())
    }

    var body: some View {
        ZStack {
            AppBackground()
            Form {
                accountSection
                imageHostSection
                serverSection
                aboutSection
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsDoneButton {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await sessionController.load()
            if authorName.isEmpty {
                authorName = sessionController.authorName ?? ""
            }
            if authorURL.isEmpty {
                authorURL = sessionController.authorURL ?? ""
            }
        }
        .confirmationDialog(
            "重新生成匿名账号？",
            isPresented: $isShowingRevokeConfirmation,
            titleVisibility: .visible
        ) {
            Button("撤销并重新生成", role: .destructive) {
                Task { @MainActor in await revokeAccount() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("当前 token 将被撤销。下次发布时会自动创建新账号，已有文章不受影响。")
        }
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .overlay(alignment: .bottom) {
            if let statusMessage {
                Text(statusMessage)
                    .font(.footnote.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .appGlass(cornerRadius: 16, brandTint: true, allowsShadow: false)
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .onChange(of: authorName) { _, _ in
            persistAuthorProfile()
        }
        .onChange(of: authorURL) { _, _ in
            persistAuthorProfile()
        }
        .onChange(of: imagePassword) { _, newValue in
            persistImagePassword(newValue)
        }
    }

    private var accountSection: some View {
        Section {
            HStack {
                Text("当前账号")
                Spacer()
                Text(sessionController.shortName.map { "@\($0)" } ?? "未登录")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            TextField("作者名（可选）", text: $authorName)
                .textInputAutocapitalization(.sentences)
            TextField("作者链接（可选）", text: $authorURL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Button("重新生成账号", role: .destructive) {
                isShowingRevokeConfirmation = true
            }
        } header: {
            Text("账号")
        } footer: {
            Text("未登录时会在首次发布时自动创建匿名账号。")
        }
    }

    private var imageHostSection: some View {
        Section {
            Picker("Provider", selection: $imageProviderRaw) {
                ForEach(ImageProvider.allCases) { provider in
                    Text(provider.displayName).tag(provider.rawValue)
                }
            }

            if selectedImageProvider == .quax {
                HStack {
                    Text("上传地址")
                    Spacer()
                    Text(QuAxHost.endpoint.absoluteString)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            } else {
                TextField("图床 baseURL", text: $imageBaseURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Toggle("Basic Auth", isOn: $imageBasicAuthEnabled)
                if imageBasicAuthEnabled {
                    TextField("用户名", text: $imageUsername)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("密码", text: $imagePassword)
                }
            }
        } header: {
            Text("图床")
        } footer: {
            Text("图片会先压缩为 JPEG，再上传到选定的 Provider。密码仅保存在 Keychain。")
        }
    }

    private var serverSection: some View {
        Section {
            Picker("服务器镜像", selection: mirrorBinding) {
                ForEach(ServerManager.Mirror.allCases) { mirror in
                    Text(mirror.displayName).tag(mirror)
                }
            }

            if serverManager.current == .custom {
                TextField("自定义 API baseURL", text: customAPIBaseBinding)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            HStack {
                Text("当前地址")
                Spacer()
                Text(serverManager.apiBase)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
            }
        } header: {
            Text("服务器")
        } footer: {
            Text("telegra.ph、graph.org、legra.ph 或自定义 API 镜像。")
        }
    }

    private var aboutSection: some View {
        Section {
            HStack {
                Text("版本")
                Spacer()
                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("开源许可")
                Spacer()
                Text("MIT")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("关于")
        }
    }

    private var selectedImageProvider: ImageProvider {
        ImageProvider(rawValue: imageProviderRaw) ?? .quax
    }

    private var mirrorBinding: Binding<ServerManager.Mirror> {
        Binding(
            get: { serverManager.current },
            set: {
                serverManager.current = $0
                sessionController.synchronizeOrigin()
            }
        )
    }

    private var customAPIBaseBinding: Binding<String> {
        Binding(
            get: { serverManager.customAPIBase },
            set: {
                serverManager.customAPIBase = $0
                sessionController.synchronizeOrigin()
            }
        )
    }

    private func persistAuthorProfile() {
        do {
            try sessionController.updateAuthorProfile(name: authorName, url: authorURL)
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    private func persistImagePassword(_ password: String) {
        do {
            if password.isEmpty {
                tokenStore.delete(ImageHostConfiguration.passwordKey)
            } else {
                try tokenStore.saveString(password, for: ImageHostConfiguration.passwordKey)
            }
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    private func revokeAccount() async {
        do {
            try await sessionController.revokeAccess()
            statusMessage = "账号已撤销，下次发布时会重新生成。"
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            statusMessage = nil
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }
}

/// 可选图床 Provider。
enum ImageProvider: String, CaseIterable, Identifiable, Equatable {
    case quax
    case telegraph
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .quax: "qu.ax"
        case .telegraph: "Telegraph 兼容"
        case .custom: "自定义"
        }
    }
}

/// 图床配置的持久化键与运行时装配逻辑。
enum ImageHostConfiguration {
    static let providerKey = "image_provider"
    static let baseURLKey = "image_base_url"
    static let usernameKey = "image_basic_auth_username"
    static let passwordKey = "image_basic_auth_password"
    static let basicAuthKey = "image_basic_auth_enabled"

    static func configurationError(
        defaults: UserDefaults = .standard
    ) -> TelegraphError? {
        let provider = ImageProvider(
            rawValue: defaults.string(forKey: providerKey) ?? ImageProvider.quax.rawValue
        ) ?? .quax
        guard provider != .quax else { return nil }
        let configuredBaseURL = defaults.string(forKey: baseURLKey)
            ?? TelegraphCompatHost.defaultBaseURL.absoluteString
        guard let url = URL(string: configuredBaseURL), isHTTPURL(url) else {
            return .api(message: "图床 baseURL 无效")
        }
        return nil
    }

    static func makeUploadService(
        defaults: UserDefaults = .standard,
        tokenStore: TokenStore = TokenStore()
    ) -> ImageUploadService {
        let provider = ImageProvider(
            rawValue: defaults.string(forKey: providerKey) ?? ImageProvider.quax.rawValue
        ) ?? .quax
        let configuredBaseURL = defaults.string(forKey: baseURLKey)
            ?? TelegraphCompatHost.defaultBaseURL.absoluteString
        let baseURL = URL(string: configuredBaseURL).flatMap { isHTTPURL($0) ? $0 : nil }
            ?? TelegraphCompatHost.defaultBaseURL
        let useAuth = defaults.bool(forKey: basicAuthKey)
        let basicAuth: (user: String, pass: String)? = {
            guard useAuth else { return nil }
            let user = defaults.string(forKey: usernameKey) ?? ""
            let pass = tokenStore.loadString(passwordKey) ?? ""
            guard !user.isEmpty || !pass.isEmpty else { return nil }
            return (user: user, pass: pass)
        }()

        switch provider {
        case .quax:
            return ImageUploadService(hosts: [QuAxHost()])
        case .telegraph, .custom:
            return ImageUploadService(hosts: [
                TelegraphCompatHost(baseURL: baseURL, basicAuth: basicAuth)
            ])
        }
    }
}

#Preview {
    NavigationStack { SettingsView() }
}
