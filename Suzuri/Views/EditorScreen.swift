import SwiftUI

/// 文章编辑与发布界面。
///
/// D5 保留页面/草稿/会话生命周期；D3 的 `BlockEditorDocument` 是正文唯一数据源。
@MainActor
struct EditorScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var draftID: UUID
    private let draftStore: DraftStore
    /// Optional test injection; production creates the pipeline from current settings per upload.
    private let injectedImagePipeline: ImagePipeline?

    @State private var sessionController: SessionController
    @State private var reachability = Reachability()
    @State private var currentPage: Page?
    @State private var targetPagePath: String?
    @State private var document: BlockEditorDocument
    @State private var title: String
    @State private var authorName: String
    @State private var isPublishing = false
    @State private var isPickingImage = false
    @State private var isUploadingImage = false
    @State private var isLoadingPage = false
    @State private var isHydrating = true
    @State private var publishedURL: URL?
    @State private var errorMessage: String?
    @State private var isPageLoadError = false
    @State private var isDraftSaveError = false
    @State private var requestGeneration = 0
    @State private var isCancelled = false
    @State private var remoteEditUnavailable = false
    @State private var hasUnsupportedContent = false
    @State private var isUnpublishedDraft = false
    @State private var hasUnsavedChanges = false
    @State private var isSuppressingChanges = false
    @State private var isShowingExitConfirmation = false
    @State private var canRetryError = false
    @State private var imageUploadErrorMessage: String?
    @State private var retryImageData: Data?
    @State private var imageProviderMessage: String?

    init(
        draftID: UUID? = nil,
        page: Page? = nil,
        sessionController: SessionController,
        draftStore: DraftStore,
        imagePipeline: ImagePipeline? = nil
    ) {
        let initialBlocks: [Block]
        if let content = page?.content {
            let decoded = BlockDecoder.decode(content)
            initialBlocks = decoded.isEmpty ? [.emptyParagraph()] : decoded
        } else {
            initialBlocks = [.emptyParagraph()]
        }

        self._draftID = State(initialValue: draftID ?? UUID())
        self.draftStore = draftStore
        self.injectedImagePipeline = imagePipeline
        self._sessionController = State(initialValue: sessionController)
        self._currentPage = State(initialValue: page)
        self._targetPagePath = State(initialValue: page?.path)
        self._hasUnsupportedContent = State(
            initialValue: page?.content.map { BlockDecoder.containsUnsupportedNodes($0) } ?? false
        )
        self._document = State(initialValue: BlockEditorDocument(blocks: initialBlocks))
        self._title = State(initialValue: page?.title ?? "")
        self._authorName = State(initialValue: page?.authorName ?? sessionController.authorName ?? "")
    }

    @MainActor
    init() {
        self.init(
            draftID: nil,
            page: nil,
            sessionController: SessionController(),
            draftStore: DraftStore(),
            imagePipeline: nil
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ReachabilityBanner(isConnected: reachability.isConnected)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if isLoadingPage {
                            ProgressView("正在拉取文章…")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        TextField("无标题", text: $title)
                            .font(.largeTitle.weight(.bold))
                            .textInputAutocapitalization(.sentences)
                            .submitLabel(.next)
                            .disabled(!canEdit || isHydrating || isPublishing)

                        TextField("作者名（可选）", text: $authorName)
                            .font(.subheadline)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .appGlass(cornerRadius: 999)
                            .disabled(!canEdit || isHydrating || isPublishing)

                        Divider()
                            .opacity(0.4)

                        // D3 block editor owns all structured text, lists, figures, and focus state.
                        BlockEditorView(isEditable: canEdit && !isHydrating && !isPublishing)
                            .frame(minHeight: 240, maxHeight: 480)
                            .environment(document)

                        if let imageProviderMessage {
                            Label(imageProviderMessage, systemImage: "checkmark.circle")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        if hasUnsupportedContent {
                            Label("页面包含暂不支持的内容，发布前请在浏览器中编辑", systemImage: "exclamationmark.triangle")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        }

                        if let currentPage, !currentPage.canEdit,
                           let url = browserURL(for: currentPage) {
                            Link(destination: url) {
                                Label("在浏览器打开", systemImage: "safari")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.brand600)
                            }
                            .padding(.top, 4)
                        }

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
                    .padding(.bottom, 120)
                }
            }
            .navigationTitle(currentPage == nil ? "新文章" : "编辑文章")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .safeAreaInset(edge: .bottom) {
                if canEdit {
                    publishBar
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        requestDismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel("返回文章列表")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView(sessionController: sessionController)
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("设置")
                }
            }
            .onAppear {
                isCancelled = false
            }
            .task {
                await loadInitialContent()
            }
            .onChange(of: title) { _, _ in
                markChangedAndScheduleSave()
            }
            .onChange(of: authorName) { _, newValue in
                markChangedAndScheduleSave()
                if !isHydrating {
                    try? sessionController.updateAuthorProfile(
                        name: newValue,
                        url: sessionController.authorURL
                    )
                }
            }
            .onChange(of: document.blocks) { _, _ in
                markChangedAndScheduleSave()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .background {
                    saveDraftNow()
                }
            }
            .onChange(of: reachability.isConnected) { wasConnected, isConnected in
                guard !wasConnected, isConnected,
                      let path = editPath,
                      isPageLoadError || currentPage?.content == nil
                else { return }
                Task { @MainActor in
                    await refreshPage(
                        path: path,
                        preserveLocalDraft: draftStore.loadUnpublished(
                            pagePath: path,
                            origin: draftOrigin,
                            accountFingerprint: draftAccountFingerprint
                        ) != nil
                    )
                }
            }
            .onDisappear {
                saveDraftNow()
                isCancelled = true
                requestGeneration += 1
            }
            .alert("图片上传失败", isPresented: Binding(
                get: { imageUploadErrorMessage != nil },
                set: {
                    if !$0 {
                        imageUploadErrorMessage = nil
                        retryImageData = nil
                    }
                }
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
            .alert(
                isPageLoadError ? "加载失败" : (isDraftSaveError ? "草稿保存失败" : "发布失败"),
                isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                if canRetryError {
                    Button("重试") {
                        Task { @MainActor in
                            if isPageLoadError, let path = editPath {
                                remoteEditUnavailable = false
                                await refreshPage(
                                    path: path,
                                    preserveLocalDraft: draftStore.loadUnpublished(
                                        pagePath: path,
                                        origin: draftOrigin,
                                        accountFingerprint: draftAccountFingerprint
                                    ) != nil
                                )
                            } else {
                                await publish()
                            }
                        }
                    }
                }
                Button("好", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .alert("有未发布草稿，确定退出？", isPresented: $isShowingExitConfirmation) {
                Button("退出", role: .destructive) {
                    dismiss()
                }
                Button("继续编辑", role: .cancel) {}
            } message: {
                Text("当前内容已保存在本地草稿中。退出后仍可从文章列表继续编辑。")
            }
            .sensoryFeedback(.success, trigger: publishedURL)
        }
    }

    /// 底部发布栏：图片选择、草稿状态和发布按钮。
    private var publishBar: some View {
        HStack(spacing: 10) {
            if isUploadingImage {
                ProgressView("上传中…")
                    .font(.footnote)
                    .tint(Color.brand600)
                    .frame(maxWidth: .infinity)
            } else {
                PhotoPickerButton(
                    onImageData: { data in
                        Task { @MainActor in await uploadImage(data) }
                    },
                    onError: { error in
                        imageUploadErrorMessage = ErrorPresenter.message(for: error)
                        retryImageData = nil
                    },
                    onLoadingChanged: { isLoading in
                        isPickingImage = isLoading
                    }
                )
                .disabled(isPublishing || isHydrating || isPickingImage)
                .frame(maxWidth: .infinity)
            }

            Circle()
                .fill(hasContent ? Color.brand600 : Color.secondary.opacity(0.4))
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)

            AppGlassButton(
                title: "发布",
                systemImage: "paperplane.fill",
                style: .primary,
                isLoading: isPublishing
            ) {
                Task { @MainActor in await publish() }
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
        document.blocks.contains { block in
            if case .divider = block {
                return true
            }
            return !block.isEmpty
        } || !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canEdit: Bool {
        guard !remoteEditUnavailable,
              currentPage?.canEdit ?? true
        else { return false }
        guard let path = editPath else { return true }
        guard sessionController.accessToken != nil else { return false }
        return currentPage?.content != nil || draftStore.loadUnpublished(
            pagePath: path,
            origin: draftOrigin,
            accountFingerprint: draftAccountFingerprint
        ) != nil
    }

    private var canPublish: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isPublishing
            && !isUploadingImage
            && !isPickingImage
            && !isHydrating
            && !isLoadingPage
            && !hasUnsupportedContent
            && (!isPageLoadError || currentPage?.content != nil)
            && canEdit
    }

    private var editPath: String? {
        currentPage?.path ?? targetPagePath
    }

    private var draftOrigin: String {
        sessionController.currentOrigin
    }

    private var draftAccountFingerprint: String {
        sessionController.accountFingerprint
    }

    private func saveCurrentDraft() throws {
        try draftStore.saveNow(
            id: draftID,
            title: title,
            blocks: document.blocks,
            origin: draftOrigin,
            accountFingerprint: draftAccountFingerprint
        )
    }

    private var shouldConfirmExit: Bool {
        isUnpublishedDraft && (hasUnsavedChanges || hasContent)
    }

    private func requestDismiss() {
        guard !isPublishing, !isUploadingImage, !isPickingImage else { return }
        if shouldConfirmExit {
            isShowingExitConfirmation = true
        } else {
            dismiss()
        }
    }

    private func browserURL(for page: Page) -> URL? {
        if let url = URL(string: page.url), isHTTPURL(url) {
            return url
        }
        return URL(string: "https://telegra.ph/\(page.path)")
    }

    private func markChangedAndScheduleSave() {
        guard !isCancelled, !isHydrating, !isSuppressingChanges, !isPublishing, canEdit else { return }
        let isFirstChange = !hasUnsavedChanges
        hasUnsavedChanges = true
        isUnpublishedDraft = true
        if isFirstChange {
            do {
                try saveCurrentDraft()
                if let targetPagePath {
                    let pathSaved = draftStore.setPagePath(
                        id: draftID,
                        pagePath: targetPagePath,
                        origin: draftOrigin,
                        accountFingerprint: draftAccountFingerprint
                    )
                    if !pathSaved, let error = draftStore.lastSaveError {
                        presentDraftSaveError(error)
                    }
                }
            } catch {
                presentDraftSaveError(error)
            }
        }
        scheduleDraftSaveIfNeeded()
    }

    private func saveDraftNow() {
        guard !isCancelled, !isHydrating, canEdit,
              isUnpublishedDraft || hasUnsavedChanges
        else { return }
        do {
            try saveCurrentDraft()
        } catch {
            presentDraftSaveError(error)
        }
    }

    private func presentDraftSaveError(_ error: Error) {
        errorMessage = "草稿保存失败：\(ErrorPresenter.message(for: error))"
        isPageLoadError = false
        isDraftSaveError = true
        canRetryError = true
    }

    private func scheduleDraftSaveIfNeeded() {
        guard !isCancelled, !isHydrating, canEdit else { return }
        draftStore.scheduleSave(
            id: draftID,
            title: title,
            blocks: document.blocks,
            origin: draftOrigin,
            accountFingerprint: draftAccountFingerprint
        )
    }

    private func loadInitialContent() async {
        guard !isCancelled else { return }
        isHydrating = true
        isSuppressingChanges = true
        hasUnsavedChanges = false
        await sessionController.load()
        guard !isCancelled else { return }
        let existingDraft = draftStore.load(
            id: draftID,
            origin: draftOrigin,
            accountFingerprint: draftAccountFingerprint
        )
        targetPagePath = existingDraft?.pagePath ?? currentPage?.path
        isUnpublishedDraft = existingDraft.map { !$0.isPublished } ?? false

        if let existingDraft {
            title = existingDraft.title
            if let savedBlocks = try? JSONDecoder().decode([Block].self, from: existingDraft.blocksData),
               !savedBlocks.isEmpty {
                document.blocks = savedBlocks
            }
        }

        if let page = currentPage {
            await refreshPage(path: page.path, preserveLocalDraft: existingDraft != nil)
        } else if let path = existingDraft?.pagePath {
            // A draft opened from the draft section can still be an edit of a remote page.
            await refreshPage(path: path, preserveLocalDraft: true)
        } else if existingDraft == nil {
            // Do not seed an editable page draft until its remote content has hydrated.
            do {
                try saveCurrentDraft()
                isUnpublishedDraft = true
            } catch {
                presentDraftSaveError(error)
            }
        }

        // Keep both guards active until all restored state has been assigned.
        isSuppressingChanges = false
        isHydrating = false
    }

    private func refreshPage(path: String, preserveLocalDraft: Bool) async {
        guard !isCancelled else { return }
        requestGeneration += 1
        let generation = requestGeneration
        isLoadingPage = currentPage?.content == nil
        defer {
            if generation == requestGeneration {
                isLoadingPage = false
            }
        }

        let requestOrigin = sessionController.currentOrigin
        let requestToken = sessionController.accessToken
        do {
            let originalPage = currentPage
            let client = try sessionController.validatedClient()
            var fetchedPage = try await PageService(client: client)
                .getPage(path: path, returnContent: true)
            guard generation == requestGeneration,
                  requestOrigin == sessionController.currentOrigin,
                  requestToken == sessionController.accessToken,
                  !isCancelled,
                  !Task.isCancelled
            else { return }
            let hasLocalDraft = draftStore.loadUnpublished(
                pagePath: path,
                origin: draftOrigin,
                accountFingerprint: draftAccountFingerprint
            ) != nil
            if fetchedPage.content == nil,
               originalPage?.content == nil,
               !hasLocalDraft {
                throw TelegraphError.invalidResponse
            }
            if fetchedPage.content == nil, let cachedContent = originalPage?.content {
                fetchedPage.content = cachedContent
            }
            hasUnsupportedContent = fetchedPage.content.map {
                BlockDecoder.containsUnsupportedNodes($0)
            } ?? false
            let permissionSource = sessionController.accessToken != nil
                && originalPage?.hasCanEditField == true
                ? originalPage
                : nil
            let remotePage = fetchedPage.preservingCanEdit(
                from: permissionSource,
                fallback: sessionController.accessToken != nil
                    && preserveLocalDraft
                    && targetPagePath != nil
            )
            currentPage = remotePage
            targetPagePath = remotePage.path
            errorMessage = nil
            canRetryError = false
            isPageLoadError = false
            isDraftSaveError = false

            if !preserveLocalDraft {
                // Keep mutation observers quiet while remote state is applied.
                let wasHydrating = isHydrating
                let wasSuppressingChanges = isSuppressingChanges
                isHydrating = true
                isSuppressingChanges = true
                title = remotePage.title
                authorName = remotePage.authorName ?? sessionController.authorName ?? ""
                if let content = remotePage.content {
                    let decoded = BlockDecoder.decode(content)
                    if !decoded.isEmpty {
                        document.blocks = decoded
                    }
                }
                isHydrating = wasHydrating
                isSuppressingChanges = wasSuppressingChanges
            }
        } catch {
            guard generation == requestGeneration,
                  requestOrigin == sessionController.currentOrigin,
                  requestToken == sessionController.accessToken,
                  !isCancelled,
                  !Task.isCancelled
            else { return }
            // Cached content remains usable. Surface a retry without turning it into publish.
            if sessionController.handleAuthenticationFailure(error), editPath != nil {
                remoteEditUnavailable = true
                currentPage = currentPage?.withCanEdit(false)
            }
            errorMessage = ErrorPresenter.message(for: error)
            canRetryError = ErrorPresenter.isRetryable(error)
            isPageLoadError = true
        }
    }

    /// 统一执行压缩、缓存和上传；成功后把图片块插入当前焦点之后。
    private func uploadImage(_ sourceData: Data) async {
        guard !isCancelled, canEdit, !isHydrating, !isPublishing else { return }
        requestGeneration += 1
        let generation = requestGeneration
        isUploadingImage = true
        imageUploadErrorMessage = nil
        retryImageData = nil
        defer { isUploadingImage = false }

        do {
            if injectedImagePipeline == nil,
               let configurationError = ImageHostConfiguration.configurationError() {
                throw configurationError
            }
            let pipeline = injectedImagePipeline
                ?? ImagePipeline(uploadService: ImageHostConfiguration.makeUploadService())
            let result = try await pipeline.processAndUpload(sourceData)
            guard !isCancelled, generation == requestGeneration else { return }
            let imageBlock = Block.figure(id: UUID(), imageURL: result.url, caption: "")
            if let focusedID = document.focusedBlockID,
               let index = document.index(of: focusedID) {
                document.insertBlock(imageBlock, at: index + 1)
            } else {
                document.blocks.append(imageBlock)
            }
            do {
                try saveCurrentDraft()
            } catch {
                presentDraftSaveError(error)
            }
            imageProviderMessage = "图片已上传（\(result.providerID)）"
        } catch {
            retryImageData = sourceData
            imageUploadErrorMessage = ErrorPresenter.message(for: error)
        }
    }

    /// 新建页面走 createPage，已发布页面走 editPage。
    private func publish() async {
        guard !isCancelled, canPublish else { return }
        requestGeneration += 1
        let generation = requestGeneration
        isPublishing = true
        errorMessage = nil
        isPageLoadError = false
        isDraftSaveError = false
        canRetryError = false
        defer { isPublishing = false }

        var requestOrigin: String?
        var requestToken: String?
        do {
            let contentBlocks = document.blocks
            // Persist the failed publish as a local draft, but reject oversized content before
            // account creation so an invalid first publish does not create an unused account.
            do {
                try saveCurrentDraft()
            } catch {
                presentDraftSaveError(error)
                throw error
            }
            let nodes = BlockEncoder.nodesForPublishing(contentBlocks)
            try BlockEncoder.validateSize(of: nodes)
            let client = try await sessionController.ensureAccount()
            guard !isCancelled, generation == requestGeneration else { return }
            guard draftStore.adoptScope(
                id: draftID,
                origin: draftOrigin,
                accountFingerprint: draftAccountFingerprint
            ) else {
                throw draftStore.lastSaveError ?? DraftStore.DraftStoreError.notFound
            }
            requestOrigin = sessionController.currentOrigin
            requestToken = sessionController.accessToken
            let service = PageService(client: client)
            let result: Page

            if let path = editPath {
                guard currentPage?.content != nil
                    || draftStore.loadUnpublished(
                        pagePath: path,
                        origin: draftOrigin,
                        accountFingerprint: draftAccountFingerprint
                    ) != nil
                else {
                    throw TelegraphError.invalidResponse
                }
                let response = try await service.editPage(
                    path: path,
                    title: title,
                    authorName: optionalValue(authorName),
                    authorUrl: sessionController.authorURL ?? currentPage?.authorUrl,
                    content: nodes
                )
                guard generation == requestGeneration,
                      requestOrigin == sessionController.currentOrigin,
                      requestToken == sessionController.accessToken,
                      !isCancelled,
                      !Task.isCancelled
                else { return }
                result = response.preservingCanEdit(
                    from: currentPage?.hasCanEditField == true ? currentPage : nil,
                    fallback: true
                )
            } else {
                let created = try await service.createPage(
                    title: title,
                    authorName: optionalValue(authorName),
                    authorUrl: sessionController.authorURL,
                    content: nodes
                )
                guard generation == requestGeneration,
                      requestOrigin == sessionController.currentOrigin,
                      requestToken == sessionController.accessToken,
                      !isCancelled,
                      !Task.isCancelled
                else { return }
                result = created.hasCanEditField ? created : created.withCanEdit(true)
            }

            guard let url = URL(string: result.url), isHTTPURL(url) else {
                throw TelegraphError.invalidResponse
            }
            var localPublishPersistenceFailed = false
            do {
                try saveCurrentDraft()
            } catch {
                localPublishPersistenceFailed = true
            }
            currentPage = result
            targetPagePath = result.path
            let markedPublished = draftStore.markPublished(
                id: draftID,
                pagePath: result.path,
                origin: draftOrigin,
                accountFingerprint: draftAccountFingerprint
            )
            if !markedPublished {
                localPublishPersistenceFailed = true
            }
            if localPublishPersistenceFailed {
                imageProviderMessage = "文章已发布，但本地草稿保存失败"
            }

            isUnpublishedDraft = false
            hasUnsavedChanges = false
            withAnimation(AppAnimation.listInsert) {
                publishedURL = url
            }
            NotificationCenter.default.post(name: .pageDidPublish, object: result)
        } catch {
            guard generation == requestGeneration, !isCancelled else { return }
            if let requestOrigin,
               let requestToken,
               requestOrigin != sessionController.currentOrigin
                    || requestToken != sessionController.accessToken {
                return
            }
            if sessionController.handleAuthenticationFailure(error), editPath != nil {
                remoteEditUnavailable = true
                currentPage = currentPage?.withCanEdit(false)
            }
            errorMessage = ErrorPresenter.message(for: error)
            canRetryError = ErrorPresenter.isRetryable(error)
        }
    }

    private func optionalValue(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

#Preview {
    EditorScreen()
}
