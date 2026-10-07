import SwiftUI

@MainActor
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var sessionController: SessionController
    var showsDoneButton = false
    @AppStorage(ImageHostConfiguration.providerKey) private var provider = ImageProvider.postimages.rawValue
    @AppStorage(ImageHostConfiguration.baseURLKey) private var imageBaseURL = ""
    @AppStorage(ImageHostConfiguration.usernameKey) private var imageUsername = ""
    @AppStorage(ImageHostConfiguration.basicAuthKey) private var useBasicAuth = false
    @State private var password = ""
    @State private var authorName = ""
    @State private var authorURL = ""
    @State private var showLogin = false
    @State private var showRevoke = false
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var profileLoaded = false
    private let tokenStore = TokenStore()

    init(sessionController: SessionController, showsDoneButton: Bool = false) {
        _sessionController = State(initialValue: sessionController)
        self.showsDoneButton = showsDoneButton
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 42)).foregroundStyle(SuzuriTheme.accentText)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(sessionController.shortName ?? "本地写作")
                            .font(.headline)
                        Text(sessionController.isAnonymous ? "草稿保存在这台设备" : "已连接 Telegraph")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
                Button {
                    showLogin = true
                } label: {
                    Label(sessionController.isAnonymous ? "连接 Telegram 中的 Telegraph 账号" : "连接另一个 Telegraph 账号", systemImage: "paperplane")
                }
                .disabled(isBusy)
            } header: { Text("账号") } footer: {
                Text("从 @telegraph 获取登录链接，连接后即可查看和编辑该账号的文章。也可以直接写作，首次发布时创建匿名账号。")
            }

            Section("默认署名") {
                TextField("作者名称", text: $authorName)
                TextField("作者主页（可选）", text: $authorURL)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("保存署名") { saveProfile() }
            }

            Section {
                Picker("图片服务", selection: $provider) {
                    Text("Postimages").tag(ImageProvider.postimages.rawValue)
                    Text("自定义图床").tag(ImageProvider.custom.rawValue)
                }
                if ImageHostConfiguration.usesPostimages() {
                    Label("Postimages", systemImage: "photo.on.rectangle.angled")
                    Link("打开 Postimages", destination: URL(string: "https://postimages.org/")!)
                } else {
                    TextField("HTTPS 上传服务地址", text: $imageBaseURL)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Toggle("需要用户名和密码", isOn: $useBasicAuth)
                    if useBasicAuth {
                        TextField("用户名", text: $imageUsername).textInputAutocapitalization(.never)
                        SecureField("密码", text: $password)
                            .onChange(of: password) { _, value in
                                do { try tokenStore.saveString(value, for: ImageHostConfiguration.passwordKey) }
                                catch { errorMessage = error.localizedDescription }
                            }
                    }
                }
            } header: { Text("图片") } footer: {
                Text(ImageHostConfiguration.usesPostimages()
                     ? "编辑时打开 Postimages 上传图片，复制 Direct link 后即可插入。原有文章中的图片链接保持不变。"
                     : "自定义服务需兼容 Telegraph 的 /upload 接口。图片经压缩后上传，密码保存在系统钥匙串。")
            }

            Section("连接") {
                Picker("服务器", selection: Binding(
                    get: { sessionController.serverManager.current },
                    set: { sessionController.serverManager.current = $0; sessionController.synchronizeOrigin() }
                )) {
                    ForEach(ServerManager.Mirror.allCases) { Text($0.displayName).tag($0) }
                }
                if sessionController.serverManager.current == .custom {
                    TextField("HTTPS API 地址", text: Binding(
                        get: { sessionController.serverManager.customAPIBase },
                        set: { sessionController.serverManager.customAPIBase = $0; sessionController.synchronizeOrigin() }
                    ))
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                if let error = sessionController.serverManager.configurationError {
                    Text(ErrorPresenter.message(for: error)).font(.footnote).foregroundStyle(.red)
                }
            }
            .disabled(isBusy)

            Section {
                LabeledContent("Suzuri · 硯", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                Text("写下想法，分享一篇好文章。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if !sessionController.isAnonymous {
                Section {
                    Button("撤销当前账号访问", role: .destructive) { showRevoke = true }
                        .disabled(isBusy)
                } footer: { Text("撤销后将无法继续通过当前令牌管理文章。请先确认能从 @telegraph 重新登录该账号。") }
            }
        }
        .scrollContentBackground(.hidden)
        .background(SuzuriTheme.background)
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsDoneButton {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() }.disabled(isBusy) }
            }
        }
        .task {
            guard !profileLoaded else { return }
            profileLoaded = true
            authorName = sessionController.authorName ?? ""
            authorURL = sessionController.authorURL ?? ""
            password = tokenStore.loadString(ImageHostConfiguration.passwordKey) ?? ""
            ImageHostConfiguration.migrateProvider()
        }
        .sheet(isPresented: $showLogin) {
            TelegraphLoginView { token in
                // A Telegram authorization token must never be sent to a custom mirror.
                sessionController.serverManager.current = .telegraph
                sessionController.synchronizeOrigin()
                try await sessionController.importAccessToken(token)
            }
        }
        .confirmationDialog("撤销当前账号访问？", isPresented: $showRevoke, titleVisibility: .visible) {
            Button("撤销访问", role: .destructive) {
                isBusy = true
                Task { @MainActor in
                    defer { isBusy = false }
                    do { try await sessionController.revokeAccess() }
                    catch { errorMessage = ErrorPresenter.message(for: error) }
                }
            }
        } message: {
            Text("文章不会删除，但当前访问凭据将失效。没有其他登录方式时，可能无法再管理这些文章。")
        }
        .alert("操作未完成", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    private func saveProfile() {
        do { try sessionController.updateAuthorProfile(name: authorName, url: authorURL) }
        catch { errorMessage = ErrorPresenter.message(for: error) }
    }
}

enum ImageProvider: String, CaseIterable, Identifiable {
    case postimages, custom
    var id: String { rawValue }
}

enum ImageHostConfiguration {
    static let providerKey = "image_provider"
    static let baseURLKey = "image_base_url"
    static let usernameKey = "image_basic_auth_username"
    static let passwordKey = "image_basic_auth_password"
    static let basicAuthKey = "image_basic_auth_enabled"

    static func migrateProvider(defaults: UserDefaults = .standard) {
        let old = defaults.string(forKey: providerKey)
        if old == "telegraph" { defaults.set(ImageProvider.custom.rawValue, forKey: providerKey) }
        else if old != ImageProvider.custom.rawValue && old != ImageProvider.postimages.rawValue {
            defaults.set(ImageProvider.postimages.rawValue, forKey: providerKey)
        }
    }

    static func usesPostimages(defaults: UserDefaults = .standard) -> Bool {
        let value = defaults.string(forKey: providerKey)
        return value != "custom" && value != "telegraph"
    }

    static func configurationError(defaults: UserDefaults = .standard) -> TelegraphError? {
        guard !usesPostimages(defaults: defaults) else { return nil }
        guard let value = defaults.string(forKey: baseURLKey), let url = URL(string: value),
              url.scheme == "https", url.host != nil, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil else {
            return .api(message: "请输入有效的 HTTPS 图床地址")
        }
        return nil
    }

    static func makeUploadService(defaults: UserDefaults = .standard,
                                  tokenStore: TokenStore = TokenStore()) throws -> ImageUploadService {
        guard !usesPostimages(defaults: defaults) else {
            throw HostError.uploadFailed("请通过 Postimages 上传窗口添加图片")
        }
        if let error = configurationError(defaults: defaults) { throw error }
        guard let raw = defaults.string(forKey: baseURLKey), let url = URL(string: raw) else {
            throw HostError.badResponse
        }
        let auth: (user: String, pass: String)? = defaults.bool(forKey: basicAuthKey)
            ? (defaults.string(forKey: usernameKey) ?? "", tokenStore.loadString(passwordKey) ?? "") : nil
        return ImageUploadService(hosts: [TelegraphCompatHost(baseURL: url, basicAuth: auth)])
    }
}
