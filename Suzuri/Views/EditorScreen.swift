import SwiftUI
import UIKit

/// 文章编辑与发布界面。
///
/// D5 保留页面/草稿/会话生命周期；D3 的 `BlockEditorDocument` 是正文唯一数据源。
@MainActor
struct EditorScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var draftID: UUID
    private let draftStore: DraftStore
    private let expectsExistingDraft: Bool
    @State private var editorOrigin: String
    @State private var editorAccount: String
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
    @State private var uploadingFigureID: UUID?
    @State private var isLoadingPage = false
    @State private var isHydrating = true
    @State private var publishedURL: URL?
    @State private var errorMessage: String?
    @State private var isPageLoadError = false
    @State private var isDraftSaveError = false
    @State private var requestGeneration = 0
    @State private var imageRequestGeneration = 0
    @State private var isDraftCorrupt = false
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
    @State private var retryFigureID: UUID?
    @State private var imageProviderMessage: String?
    @State private var isShowingPostimages = false
    @State private var pendingImageTarget: UUID?
    @State private var replacesPendingFigure = false

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
        self.expectsExistingDraft = draftID != nil && page == nil
        self._editorOrigin = State(initialValue: sessionController.currentOrigin)
        self._editorAccount = State(initialValue: sessionController.accountFingerprint)
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

    private var editorCanvas: some View {
        BlockEditorView(
            isEditable: canEdit && !isHydrating && !isPublishing,
            isImageActionEnabled: isImageActionEnabled,
            uploadingFigureID: uploadingFigureID,
            onImageData: { data, targetID in
                Task { @MainActor in await uploadImage(data, intoFigure: targetID) }
            },
            onImageError: { error, targetID in
                imageUploadErrorMessage = ErrorPresenter.message(for: error)
                retryImageData = nil
                retryFigureID = targetID
            },
            onImagePickerLoadingChanged: { isPickingImage = $0 },
            onRequestImage: usesPostimages ? requestPostimages : nil,
            header: AnyView(documentHeader)
        )
        .environment(document)
        .background(SuzuriTheme.paper)
    }

    private var navigationContent: some View {
        editorCanvas
        .navigationTitle(currentPage == nil ? "新文章" : "编辑文章")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
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
                Menu {
                    ShareLink(item: exportText) { Label("导出文本", systemImage: "square.and.arrow.up") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("文章操作")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { @MainActor in await publish() }
                } label: {
                    Group {
                        if isPublishing {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text(editPath == nil ? "发布" : "更新")
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(minWidth: 58, minHeight: 20)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.brand600, in: Capsule())
                    .opacity(canPublish ? 1 : 0.4)
                }
                .disabled(!canPublish)
                .accessibilityLabel("发布")
            }
        }
    }

    private var observedEditor: some View {
        navigationContent
        .sheet(isPresented: $isShowingPostimages) {
            PostimagesUploadView { url in insertHostedImage(url) }
        }
        .onChange(of: authorName) { _, _ in markChangedAndScheduleSave() }
        .onChange(of: draftStore.lastSaveError?.localizedDescription) { _, value in
            if value != nil, let error = draftStore.lastSaveError { presentDraftSaveError(error) }
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
        .onChange(of: document.blocks) { _, _ in
            markChangedAndScheduleSave()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                commitTextInput()
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
            imageRequestGeneration += 1
        }
    }

    private var imageAlerts: some View {
        observedEditor
        .alert("图片上传失败", isPresented: Binding(
            get: { imageUploadErrorMessage != nil },
            set: {
                if !$0 {
                    imageUploadErrorMessage = nil
                    retryImageData = nil
                    retryFigureID = nil
                }
            }
        )) {
            if retryImageData != nil {
                Button("重试") {
                    if let data = retryImageData {
                        Task { @MainActor in
                            await uploadImage(data, intoFigure: retryFigureID)
                        }
                    }
                }
            }
            Button("取消", role: .cancel) {
                imageUploadErrorMessage = nil
                retryImageData = nil
                retryFigureID = nil
            }
        } message: {
            Text(imageUploadErrorMessage ?? "")
        }
    }

    private var requestAlerts: some View {
        imageAlerts
        .alert(
            isPageLoadError ? "加载失败" : (isDraftSaveError ? "草稿保存失败" : "发布失败"),
            isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            if canRetryError {
                Button("重试") {
                    Task { @MainActor in
                        if isDraftSaveError {
                            if draftStore.retryOpeningStore() { saveDraftNow() }
                        } else if isPageLoadError, let path = editPath {
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
    }

    var body: some View {
        requestAlerts
        .alert("有未发布草稿，确定退出？", isPresented: $isShowingExitConfirmation) {
            Button("退出", role: .destructive) {
                if saveDraftNow() { dismiss() }
            }
            Button("继续编辑", role: .cancel) {}
        } message: {
            Text("退出前会再次保存草稿。保存成功后，可从文章列表继续编辑。")
        }
        .sensoryFeedback(.success, trigger: publishedURL)
    }

    private var documentHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            ReachabilityBanner(isConnected: reachability.isConnected)
            HStack(spacing: 6) {
                Circle().fill(draftStore.lastSaveError == nil ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)
                Text(isHydrating ? "正在打开…" : (draftStore.lastSaveError != nil ? "尚未保存" : "本地草稿 · 自动保存"))
                    .font(.caption).foregroundStyle(SuzuriTheme.secondaryInk)
                Spacer()
                Text("\(document.blocks.count) 个区块").font(.caption).foregroundStyle(.tertiary)
            }
            TextField("给文章起个名字", text: $title, axis: .vertical)
                .font(.system(.largeTitle, design: .serif, weight: .bold))
                .foregroundStyle(SuzuriTheme.ink)
                .disabled(!canEdit || isHydrating || isPublishing)
                .accessibilityIdentifier("editor.title")
            if !authorName.isEmpty {
                Label(authorName, systemImage: "person.crop.circle")
                    .font(.subheadline).foregroundStyle(SuzuriTheme.secondaryInk)
            }
            if isLoadingPage { ProgressView("正在读取文章…") }
            if let imageProviderMessage {
                Text(imageProviderMessage).font(.footnote).foregroundStyle(.secondary)
            }
            if hasUnsupportedContent {
                Label("这篇文章包含暂不支持的格式，为保留完整内容，请在浏览器中修改。", systemImage: "lock.doc")
                    .font(.footnote).foregroundStyle(.orange)
            }
            if let page = currentPage, (!page.canEdit || hasUnsupportedContent), let url = browserURL(for: page) {
                Link("在浏览器中打开", destination: url).font(.subheadline)
            }
            if let url = publishedURL {
                HStack {
                    Label("已发布", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    Spacer()
                    ShareLink(item: url) { Label("分享文章", systemImage: "square.and.arrow.up") }
                }
                .font(.subheadline)
                .padding(14)
                .background(SuzuriTheme.background, in: RoundedRectangle(cornerRadius: 14))
            }
            Divider().overlay(SuzuriTheme.line)
        }
    }

    private var exportText: String {
        ([title] + document.blocks.map { block in
            switch block {
            case let .figure(_, url, caption):
                return "![\(caption)](\(url?.absoluteString ?? ""))"
            case let .bulletList(_, items):
                return items.map { "- \($0.text)" }.joined(separator: "\n")
            case let .numberedList(_, items):
                return items.enumerated().map { "\($0.offset + 1). \($0.element.text)" }.joined(separator: "\n")
            case let .heading(_, level, text):
                return String(repeating: "#", count: level) + " " + text
            case let .quote(_, text): return "> " + text
            case let .code(_, text): return "```\n" + text + "\n```"
            case let .link(_, text, url): return "[\(text)](\(url.absoluteString))"
            case let .paragraph(_, text): return text
            case .divider: return "---"
            }
        }).joined(separator: "\n\n")
    }

    private var usesPostimages: Bool {
        ImageHostConfiguration.usesPostimages()
    }

    private func commitTextInput() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func requestPostimages(_ targetID: UUID?) {
        guard isImageActionEnabled else { return }
        commitTextInput()
        pendingImageTarget = targetID ?? document.focusedBlockID
        replacesPendingFigure = targetID.map { id in
            if case .figure = document.block(for: id) { return true }
            return false
        } ?? false
        isShowingPostimages = true
    }

    private func insertHostedImage(_ url: URL) {
        guard canEdit, !isCancelled else { return }
        if replacesPendingFigure {
            guard let id = pendingImageTarget,
                  case let .figure(_, _, caption) = document.block(for: id) else { return }
            document.replaceBlock(id: id, with: .figure(id: id, imageURL: url, caption: caption))
        } else {
            let index = pendingImageTarget.flatMap { document.index(of: $0) }.map { $0 + 1 }
                ?? document.blocks.count
            document.insertBlock(.figure(id: UUID(), imageURL: url, caption: ""), at: index)
        }
        markChangedAndScheduleSave()
        saveDraftNow()
        imageProviderMessage = "图片已从 Postimages 插入"
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
        guard editorOrigin == sessionController.currentOrigin,
              editorAccount == sessionController.accountFingerprint,
              !remoteEditUnavailable, !hasUnsupportedContent, !isDraftCorrupt,
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

    private var isImageActionEnabled: Bool {
        canEdit
            && !isHydrating
            && !isPublishing
            && !isUploadingImage
            && !isPickingImage
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
        editorOrigin
    }

    private var draftAccountFingerprint: String {
        editorAccount
    }

    private func saveCurrentDraft() throws {
        try draftStore.saveNow(
            id: draftID,
            title: title,
            blocks: document.blocks,
            origin: draftOrigin,
            accountFingerprint: draftAccountFingerprint
        )
        if let path = editPath,
           !draftStore.setPagePath(id: draftID, pagePath: path, origin: draftOrigin,
                                   accountFingerprint: draftAccountFingerprint) {
            throw draftStore.lastSaveError ?? DraftStore.DraftStoreError.notFound
        }
    }

    private var shouldConfirmExit: Bool {
        isUnpublishedDraft && (hasUnsavedChanges || hasContent)
    }

    private func requestDismiss() {
        guard !isPublishing, !isUploadingImage, !isPickingImage else { return }
        commitTextInput()
        guard saveDraftNow() else { return }
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
            } catch {
                presentDraftSaveError(error)
            }
        }
        scheduleDraftSaveIfNeeded()
    }

    @discardableResult
    private func saveDraftNow() -> Bool {
        guard !isCancelled, !isHydrating, !isDraftCorrupt, !hasUnsupportedContent,
              isUnpublishedDraft || hasUnsavedChanges else { return !hasUnsavedChanges }
        do {
            try saveCurrentDraft()
            isDraftSaveError = false
            errorMessage = nil
            return true
        } catch {
            presentDraftSaveError(error)
            return false
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
        if existingDraft == nil && (expectsExistingDraft || draftStore.lastReadError != nil) {
            isDraftCorrupt = true
            errorMessage = "无法读取这份草稿。请返回并确认账号和本地存储状态，原始草稿未被修改。"
            canRetryError = false
            isHydrating = false
            isSuppressingChanges = false
            return
        }
        targetPagePath = existingDraft?.pagePath ?? currentPage?.path
        isUnpublishedDraft = existingDraft.map { !$0.isPublished } ?? false

        if let existingDraft {
            title = existingDraft.title
            do {
                let savedBlocks = try JSONDecoder().decode([Block].self, from: existingDraft.blocksData)
                document.blocks = savedBlocks
            } catch {
                isDraftCorrupt = true
                errorMessage = "草稿内容无法读取，已停止自动保存以保留原始数据。"
                canRetryError = false
                isHydrating = false
                isSuppressingChanges = false
                return
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

    /// 统一执行压缩、缓存和上传；可填充指定图片块或插入当前焦点之后。
    private func uploadImage(_ sourceData: Data, intoFigure targetID: UUID? = nil) async {
        guard !isCancelled, canEdit, !isHydrating, !isPublishing else { return }
        guard !isUploadingImage else {
            retryImageData = sourceData
            retryFigureID = targetID
            imageUploadErrorMessage = "已有图片正在上传，请稍后重试"
            return
        }
        imageRequestGeneration += 1
        let generation = imageRequestGeneration
        isUploadingImage = true
        uploadingFigureID = targetID
        imageUploadErrorMessage = nil
        retryImageData = nil
        retryFigureID = nil
        defer {
            isUploadingImage = false
            if uploadingFigureID == targetID {
                uploadingFigureID = nil
            }
        }

        do {
            if injectedImagePipeline == nil,
               let configurationError = ImageHostConfiguration.configurationError() {
                throw configurationError
            }
            let pipeline: ImagePipeline
            if let injectedImagePipeline { pipeline = injectedImagePipeline }
            else { pipeline = ImagePipeline(uploadService: try ImageHostConfiguration.makeUploadService()) }
            let result = try await pipeline.processAndUpload(sourceData)
            guard !isCancelled, generation == imageRequestGeneration else { return }

            if let targetID {
                guard let current = document.block(for: targetID),
                      case let .figure(id, _, caption) = current
                else { return }
                document.replaceBlock(
                    id: targetID,
                    with: .figure(id: id, imageURL: result.url, caption: caption)
                )
            } else {
                let imageBlock = Block.figure(id: UUID(), imageURL: result.url, caption: "")
                if let focusedID = document.focusedBlockID,
                   let index = document.index(of: focusedID) {
                    document.insertBlock(imageBlock, at: index + 1)
                } else {
                    document.blocks.append(imageBlock)
                }
            }

            do {
                try saveCurrentDraft()
            } catch {
                presentDraftSaveError(error)
            }
            imageProviderMessage = "图片已上传（\(result.providerID)）"
        } catch {
            retryImageData = sourceData
            retryFigureID = targetID
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
            commitTextInput()
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
            guard editorOrigin == sessionController.currentOrigin else {
                throw TelegraphError.api(message: "服务器已改变，请重新打开文章。")
            }
            let authenticatedAccount = sessionController.accountFingerprint
            guard editorAccount == authenticatedAccount
                    || editorAccount == TokenStore.fingerprint("anonymous") else {
                throw TelegraphError.api(message: "账号已改变，请重新打开文章。")
            }
            try draftStore.adoptAnonymousDrafts(
                origin: editorOrigin, accountFingerprint: authenticatedAccount
            )
            editorAccount = authenticatedAccount
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
                    authorUrl: currentPage?.authorUrl,
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

            isUnpublishedDraft = localPublishPersistenceFailed
            hasUnsavedChanges = localPublishPersistenceFailed
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
