import SwiftUI

/// 文章编辑与发布界面。
///
/// 正文仍保留现有编辑入口；D5 负责草稿生命周期、已发布页回填、图片上传和发布分流。
@MainActor
struct EditorScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    private let draftID: UUID
    private let draftStore: DraftStore
    /// Optional test injection; production creates the pipeline from current settings per upload.
    private let injectedImagePipeline: ImagePipeline?

    @State private var sessionController: SessionController
    @State private var reachability = Reachability()
    @State private var currentPage: Page?
    @State private var title: String
    @State private var authorName: String
    @State private var bodyText: String
    @State private var blocks: [Block]
    @State private var usesStructuredBlocks: Bool
    @State private var isPublishing = false
    @State private var isUploadingImage = false
    @State private var isLoadingPage = false
    @State private var isHydrating = true
    @State private var publishedURL: URL?
    @State private var errorMessage: String?
    @State private var isUnpublishedDraft = false
    @State private var hasUnsavedChanges = false
    @State private var isShowingExitConfirmation = false
    @State private var canRetryError = false
    @State private var imageUploadErrorMessage: String?
    @State private var retryImageData: Data?
    @State private var imageProviderMessage: String?

    init(
        draftID: UUID? = nil,
        page: Page? = nil,
        sessionController: SessionController = SessionController(),
        draftStore: DraftStore = DraftStore(),
        imagePipeline: ImagePipeline? = nil
    ) {
        let initialBlocks: [Block]
        if let content = page?.content {
            let decoded = BlockDecoder.decode(content)
            initialBlocks = decoded.isEmpty ? [.emptyParagraph()] : decoded
        } else {
            initialBlocks = [.emptyParagraph()]
        }

        self.draftID = draftID ?? UUID()
        self.draftStore = draftStore
        self.injectedImagePipeline = imagePipeline
        self._sessionController = State(initialValue: sessionController)
        self._currentPage = State(initialValue: page)
        self._title = State(initialValue: page?.title ?? "")
        self._authorName = State(initialValue: page?.authorName ?? sessionController.authorName ?? "")
        self._blocks = State(initialValue: initialBlocks)
        self._bodyText = State(initialValue: Self.plainText(from: initialBlocks))
        self._usesStructuredBlocks = State(initialValue: page?.content?.isEmpty == false)
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
                            .disabled(!canEdit)

                        TextField("作者名（可选）", text: $authorName)
                            .font(.subheadline)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .appGlass(cornerRadius: 999)
                            .disabled(!canEdit)

                        Divider()
                            .opacity(0.4)

                        TextField("正文（空行分段）", text: $bodyText, axis: .vertical)
                            .font(.body)
                            .lineLimit(8...20)
                            .textInputAutocapitalization(.sentences)
                            .disabled(!canEdit)

                        if let imageProviderMessage {
                            Label(imageProviderMessage, systemImage: "checkmark.circle")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        if let currentPage, !currentPage.canEdit,
                           let url = URL(string: currentPage.url) {
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
            .task {
                await loadInitialContent()
            }
            .onChange(of: title) { _, _ in
                markChangedAndScheduleSave()
            }
            .onChange(of: authorName) { _, _ in
                markChangedAndScheduleSave()
            }
            .onChange(of: bodyText) { _, newValue in
                if !isHydrating && usesStructuredBlocks {
                    let imageBlocks = blocks.filter { block in
                        if case .figure = block { return true }
                        return false
                    }
                    blocks = Self.paragraphBlocks(from: newValue) + imageBlocks
                    usesStructuredBlocks = false
                }
                markChangedAndScheduleSave()
            }
            .onChange(of: blocks) { _, _ in
                markChangedAndScheduleSave()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .background {
                    saveDraftNow()
                }
            }
            .onChange(of: reachability.isConnected) { wasConnected, isConnected in
                guard !wasConnected, isConnected,
                      let page = currentPage,
                      page.content == nil
                else { return }
                Task { @MainActor in
                    await refreshPage(
                        path: page.path,
                        preserveLocalDraft: draftStore.loadUnpublished(pagePath: page.path) != nil
                    )
                }
            }
            .onDisappear {
                saveDraftNow()
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
            .alert("发布失败", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                if canRetryError {
                    Button("重试") {
                        Task { @MainActor in await publish() }
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
                    }
                )
                .disabled(isPublishing)
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
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || blocks.contains { !$0.isEmpty }
    }

    private var canEdit: Bool {
        currentPage?.canEdit ?? true
    }

    private var canPublish: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isPublishing
            && !isUploadingImage
            && canEdit
    }

    private var shouldConfirmExit: Bool {
        isUnpublishedDraft && (hasUnsavedChanges || hasContent)
    }

    private func requestDismiss() {
        if shouldConfirmExit {
            isShowingExitConfirmation = true
        } else {
            dismiss()
        }
    }

    /// 当前 D4 正文入口使用字符串；图片块仍以 Block 保留在同一发布内容中。
    private var blocksForPublishing: [Block] {
        let paragraphs = Self.paragraphBlocks(from: bodyText)
        let imageBlocks = blocks.filter { block in
            if case .figure = block { return true }
            return false
        }

        // When a page was decoded by the block editor, preserve its structure.
        if usesStructuredBlocks {
            return blocks
        }
        return paragraphs + imageBlocks
    }

    private func markChangedAndScheduleSave() {
        guard !isHydrating else { return }
        hasUnsavedChanges = true
        isUnpublishedDraft = true
        scheduleDraftSaveIfNeeded()
    }

    private func saveDraftNow() {
        guard !isHydrating, canEdit else { return }
        try? draftStore.saveNow(
            id: draftID,
            title: title,
            blocks: blocksForPublishing
        )
    }

    private func scheduleDraftSaveIfNeeded() {
        guard !isHydrating else { return }
        draftStore.scheduleSave(
            id: draftID,
            title: title,
            blocks: blocksForPublishing
        )
    }

    private func loadInitialContent() async {
        isHydrating = true
        hasUnsavedChanges = false
        let existingDraft = draftStore.load(id: draftID)
        isUnpublishedDraft = existingDraft?.isPublished == false

        if let existingDraft {
            title = existingDraft.title
            if let savedBlocks = try? JSONDecoder().decode([Block].self, from: existingDraft.blocksData),
               !savedBlocks.isEmpty {
                blocks = savedBlocks
                bodyText = Self.plainText(from: savedBlocks)
                usesStructuredBlocks = existingDraft.pagePath != nil
                    || savedBlocks.contains { block in
                        if case .paragraph = block {
                            return false
                        }
                        return true
                    }
            }
        }

        if let page = currentPage {
            if page.canEdit, existingDraft == nil {
                let initial = blocksForPublishing
                try? draftStore.saveNow(id: draftID, title: title, blocks: initial)
                draftStore.setPagePath(id: draftID, pagePath: page.path)
                isUnpublishedDraft = true
            }
            await refreshPage(path: page.path, preserveLocalDraft: existingDraft != nil)
        } else if existingDraft == nil {
            try? draftStore.saveNow(id: draftID, title: title, blocks: blocksForPublishing)
            isUnpublishedDraft = true
        }

        isHydrating = false
    }

    private func refreshPage(path: String, preserveLocalDraft: Bool) async {
        isLoadingPage = currentPage?.content == nil
        defer { isLoadingPage = false }

        do {
            let originalPage = currentPage
            let fetchedPage = try await PageService(client: sessionController.makeClient())
                .getPage(path: path, returnContent: true)
            let remotePage = fetchedPage.preservingCanEdit(from: originalPage)
            currentPage = remotePage
            if !preserveLocalDraft {
                title = remotePage.title
                authorName = remotePage.authorName ?? ""
                if let content = remotePage.content {
                    let decoded = BlockDecoder.decode(content)
                    if !decoded.isEmpty {
                        blocks = decoded
                        bodyText = Self.plainText(from: decoded)
                        usesStructuredBlocks = true
                    }
                }
                try? draftStore.saveNow(id: draftID, title: title, blocks: blocksForPublishing)
                draftStore.setPagePath(id: draftID, pagePath: remotePage.path)
            }
        } catch {
            // Cached content remains usable. Only surface the error when there is no cache.
            if currentPage?.content == nil {
                errorMessage = ErrorPresenter.message(for: error)
                canRetryError = ErrorPresenter.isRetryable(error)
            }
        }
    }

    /// 统一执行压缩、缓存和上传；成功后把图片块追加到待发布内容。
    private func uploadImage(_ sourceData: Data) async {
        isUploadingImage = true
        imageUploadErrorMessage = nil
        retryImageData = nil
        defer { isUploadingImage = false }

        do {
            let pipeline = injectedImagePipeline
                ?? ImagePipeline(uploadService: ImageHostConfiguration.makeUploadService())
            let result = try await pipeline.processAndUpload(sourceData)
            blocks.append(.figure(id: UUID(), imageURL: result.url, caption: ""))
            imageProviderMessage = "图片已上传（\(result.providerID)）"
        } catch {
            retryImageData = sourceData
            imageUploadErrorMessage = ErrorPresenter.message(for: error)
        }
    }

    /// 新建页面走 createPage，已发布页面走 editPage。
    private func publish() async {
        guard canPublish else { return }
        isPublishing = true
        errorMessage = nil
        canRetryError = false
        defer { isPublishing = false }

        do {
            let contentBlocks = blocksForPublishing
            try? draftStore.saveNow(id: draftID, title: title, blocks: contentBlocks)
            let nodes = BlockEncoder.nodesForPublishing(contentBlocks)
            try BlockEncoder.validateSize(of: nodes)
            let client = try await sessionController.ensureAccount()
            let service = PageService(client: client)
            let result: Page

            if let currentPage {
                let response = try await service.editPage(
                    path: currentPage.path,
                    title: title,
                    authorName: optionalValue(authorName),
                    authorUrl: sessionController.authorURL,
                    content: nodes
                )
                result = response.preservingCanEdit(from: currentPage)
            } else {
                result = try await service.createPage(
                    title: title,
                    authorName: optionalValue(authorName),
                    authorUrl: sessionController.authorURL,
                    content: nodes
                )
            }

            guard let url = URL(string: result.url), isHTTPURL(url) else {
                throw TelegraphError.invalidResponse
            }
            try? draftStore.saveNow(id: draftID, title: title, blocks: contentBlocks)
            currentPage = result
            draftStore.markPublished(id: draftID, pagePath: result.path)
            isUnpublishedDraft = false
            hasUnsavedChanges = false
            withAnimation(AppAnimation.listInsert) {
                publishedURL = url
            }
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
            canRetryError = ErrorPresenter.isRetryable(error)
        }
    }

    private func optionalValue(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func paragraphBlocks(from text: String) -> [Block] {
        text
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { Block.paragraph(id: UUID(), text: $0) }
    }

    private static func plainText(from blocks: [Block]) -> String {
        blocks.compactMap { block in
            switch block {
            case let .paragraph(_, text), let .heading(_, _, text),
                 let .quote(_, text), let .code(_, text), let .link(_, text, _):
                return text.isEmpty ? nil : text
            case let .bulletList(_, items), let .numberedList(_, items):
                let text = items.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n")
                return text.isEmpty ? nil : text
            case .divider, .figure:
                return nil
            }
        }
        .joined(separator: "\n\n")
    }
}

#Preview {
    EditorScreen()
}
