import SwiftUI
import UIKit

extension Notification.Name {
    static let pageDidPublish = Notification.Name("Suzuri.pageDidPublish")
}

/// 草稿与已发布文章列表。
@MainActor
struct PageListView: View {
    private enum Destination: Hashable {
        case draft(UUID)
        case page(Page, draftID: UUID?)
    }

    private static let hiddenPagesKey = "locally_hidden_page_paths"
    private static let cachedPagesKey = "cached_page_list"
    private let pageLimit = 50
    private let draftStore: DraftStore

    @State private var sessionController: SessionController
    @State private var reachability = Reachability()
    @State private var drafts: [Draft] = []
    @State private var pages: [Page] = []
    @State private var pageLastSeen: [String: Date] = [:]
    @State private var hiddenPagePaths: Set<String> = []
    @State private var totalPageCount = 0
    @State private var nextOffset = 0
    @State private var hasMorePages = false
    @State private var requestGeneration = 0
    @State private var isLoading = false
    @State private var isInitialLoading = false
    @State private var hasLoaded = false
    @State private var errorMessage: String?
    @State private var canRetryError = false
    @State private var path: [Destination] = []
    @State private var isShowingSettings = false
    @State private var searchText = ""
    @State private var libraryFilter = LibraryFilter.all

    private enum LibraryFilter: String, CaseIterable, Identifiable {
        case all = "全部", drafts = "草稿", published = "已发布"
        var id: String { rawValue }
    }

    private var visibleDrafts: [Draft] {
        guard libraryFilter != .published else { return [] }
        return drafts.filter { searchText.isEmpty || $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    private var visiblePages: [Page] {
        guard libraryFilter != .drafts else { return [] }
        return pages.filter {
            searchText.isEmpty || $0.title.localizedCaseInsensitiveContains(searchText)
                || $0.description.localizedCaseInsensitiveContains(searchText)
        }
    }

    init(
        sessionController: SessionController,
        draftStore: DraftStore
    ) {
        self._sessionController = State(initialValue: sessionController)
        self.draftStore = draftStore
    }

    @MainActor
    init() {
        self.init(
            sessionController: SessionController(),
            draftStore: DraftStore()
        )
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("写下此刻。")
                                .font(.system(.largeTitle, design: .serif, weight: .bold))
                                .foregroundStyle(SuzuriTheme.ink)
                            Text("从一行文字，到一篇值得分享的文章。")
                                .font(.subheadline).foregroundStyle(SuzuriTheme.secondaryInk)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "square.and.pencil")
                            .font(.title2).foregroundStyle(SuzuriTheme.accentText)
                            .padding(12).background(SuzuriTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                    }
                    .padding(.vertical, 12)
                    ReachabilityBanner(isConnected: reachability.isConnected)
                    if !draftStore.isAvailable || draftStore.lastReadError != nil || draftStore.lastSaveError != nil {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("草稿存储需要处理", systemImage: "exclamationmark.triangle")
                                .font(.headline)
                            Text("暂时无法读写本地草稿。重试成功前，请不要退出尚未保存的文章。")
                                .font(.subheadline)
                            Button("重新打开草稿库") {
                                if draftStore.retryOpeningStore() {
                                    draftStore.savePendingNow()
                                    Task { await reload() }
                                }
                            }
                        }
                        .padding(16).background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 18))
                    }
                    Picker("文章分类", selection: $libraryFilter) {
                        ForEach(LibraryFilter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.bottom, 6)
                    if !visibleDrafts.isEmpty {
                        sectionHeader("草稿 · \(visibleDrafts.count)")
                        ForEach(visibleDrafts, id: \.id) { draft in
                            Button { path.append(.draft(draft.id)) } label: { DraftRowView(draft: draft) }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button("删除草稿", systemImage: "trash", role: .destructive) { deleteDraft(draft) }
                                }
                        }
                    }
                    if !visiblePages.isEmpty {
                        sectionHeader("已发布 · \(visiblePages.count)")
                        ForEach(visiblePages) { page in
                            Button { openPage(page) } label: { PageRowView(page: page, lastSeen: pageLastSeen[page.path]) }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button("复制链接", systemImage: "link") { UIPasteboard.general.string = page.url }
                                    Button("从列表隐藏", systemImage: "eye.slash") { hidePage(page) }
                                }
                        }
                    }
                    if isLoading || isInitialLoading {
                        ProgressView("正在读取…").frame(maxWidth: .infinity).padding(28)
                    } else if visibleDrafts.isEmpty && visiblePages.isEmpty {
                        ContentUnavailableView {
                            Label(searchText.isEmpty ? "从第一句话开始" : "没有匹配的文章", systemImage: "doc.text")
                        } description: {
                            Text(searchText.isEmpty ? "草稿会自动保存在这台设备，写好后再发布。" : "试试其他标题关键词，或加载更多文章。")
                        } actions: {
                            if searchText.isEmpty {
                                Button("写新文章", action: createDraftAndOpen).buttonStyle(PrimaryActionStyle())
                                    .disabled(!draftStore.isAvailable)
                            }
                        }
                    }
                    if hasMorePages && !isLoading && libraryFilter != .drafts {
                        Button("加载更多文章") { Task { await loadMoreIfNeeded() } }
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .background(SuzuriTheme.background)
            .navigationTitle("Suzuri · 硯")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "搜索文章标题")
            .refreshable { await sessionController.load(); await reload() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { isShowingSettings = true } label: { Image(systemName: "person.crop.circle") }
                        .accessibilityLabel("账号与设置")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: createDraftAndOpen) { Image(systemName: "plus") }
                        .accessibilityLabel("写新文章").disabled(!draftStore.isAvailable)
                }
            }
            .navigationDestination(for: Destination.self) { destination in
                switch destination {
                case .draft(let id):
                    EditorScreen(draftID: id, sessionController: sessionController, draftStore: draftStore)
                case .page(let page, let draftID):
                    EditorScreen(draftID: draftID, page: page, sessionController: sessionController, draftStore: draftStore)
                }
            }
            .sheet(isPresented: $isShowingSettings, onDismiss: {
                Task { await sessionController.load(); await reload() }
            }) {
                NavigationStack { SettingsView(sessionController: sessionController, showsDoneButton: true) }
            }
            .task {
                guard !hasLoaded else { return }
                hasLoaded = true
                isInitialLoading = true
                ImageHostConfiguration.migrateProvider()
                await sessionController.load()
                await reload()
                isInitialLoading = false
            }
            .onAppear {
                guard hasLoaded, !isInitialLoading, !isLoading else { return }
                Task { await sessionController.load(); await reload() }
            }
            .onChange(of: reachability.isConnected) { wasConnected, isConnected in
                guard !wasConnected, isConnected else { return }
                Task { await sessionController.load(); await reload() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .pageDidPublish)) { notification in
                guard let page = notification.object as? Page else { return }
                upsertPublishedPage(page)
            }
            .alert("操作未完成", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) {
                if canRetryError { Button("重试") { Task { await reload() } } }
                Button("好", role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.title3.weight(.semibold))
            Spacer()
        }
        .padding(.top, 10)
        .accessibilityAddTraits(.isHeader)
    }

    private func reload() async {
        guard !Task.isCancelled else { return }
        sessionController.synchronizeOrigin()
        let requestOrigin = sessionController.currentOrigin
        let requestToken = sessionController.accessToken
        requestGeneration += 1
        let generation = requestGeneration
        isLoading = true
        errorMessage = nil
        canRetryError = false
        defer {
            if generation == requestGeneration {
                isLoading = false
            }
        }

        if !sessionController.isAnonymous {
            do {
                try draftStore.adoptAnonymousDrafts(origin: requestOrigin,
                                                    accountFingerprint: sessionController.accountFingerprint)
            } catch {
                errorMessage = ErrorPresenter.message(for: error)
            }
        }
        hiddenPagePaths = Set(UserDefaults.standard.stringArray(forKey: scopedHiddenPagesKey) ?? [])
        drafts = draftStore.loadAll(
            origin: requestOrigin,
            accountFingerprint: sessionController.accountFingerprint
        ).filter { !$0.isPublished }

        // Published pages are cached so the list remains useful after relaunching offline.
        if let cached = loadCachedPageList() {
            let fetchedAt = Date()
            for page in cached.pages {
                pageLastSeen[page.path] = fetchedAt
            }
            pages = cached.pages.filter { !hiddenPagePaths.contains($0.path) }
            nextOffset = cached.pages.count
            totalPageCount = cached.totalCount
            hasMorePages = sessionController.accessToken != nil
                && nextOffset < totalPageCount
        } else {
            pages = []
            nextOffset = 0
            totalPageCount = 0
            hasMorePages = false
        }

        // The first anonymous screen remains usable without creating an account.
        guard sessionController.accessToken != nil else { return }

        do {
            let service = try pageService()
            let result = try await service.getPageList(offset: 0, limit: pageLimit)
            guard generation == requestGeneration,
                  requestOrigin == sessionController.currentOrigin,
                  requestToken == sessionController.accessToken,
                  !Task.isCancelled
            else { return }
            let fetchedAt = Date()
            for page in result.pages {
                pageLastSeen[page.path] = fetchedAt
            }
            pages = result.pages.filter { !hiddenPagePaths.contains($0.path) }
            totalPageCount = result.total
            nextOffset = result.pages.count
            hasMorePages = !result.pages.isEmpty && nextOffset < totalPageCount
            saveCachedPageList(PageList(totalCount: result.total, pages: result.pages))
        } catch {
            guard generation == requestGeneration,
                  requestOrigin == sessionController.currentOrigin,
                  requestToken == sessionController.accessToken,
                  !Task.isCancelled
            else { return }
            if sessionController.handleAuthenticationFailure(error) {
                drafts = draftStore.loadAll(origin: sessionController.currentOrigin,
                                            accountFingerprint: sessionController.accountFingerprint)
                    .filter { !$0.isPublished }
                pages = []
                totalPageCount = 0
                nextOffset = 0
            }
            errorMessage = ErrorPresenter.message(for: error)
            canRetryError = ErrorPresenter.isRetryable(error)
            hasMorePages = false
        }
    }

    private func loadMoreIfNeeded() async {
        sessionController.synchronizeOrigin()
        let requestOrigin = sessionController.currentOrigin
        let requestToken = sessionController.accessToken
        guard !isLoading,
              requestToken != nil,
              hasMorePages,
              !Task.isCancelled
        else { return }

        let generation = requestGeneration
        isLoading = true
        defer {
            if generation == requestGeneration {
                isLoading = false
            }
        }
        do {
            let service = try pageService()
            let result = try await service.getPageList(offset: nextOffset, limit: pageLimit)
            guard generation == requestGeneration,
                  requestOrigin == sessionController.currentOrigin,
                  requestToken == sessionController.accessToken,
                  !Task.isCancelled
            else { return }
            let fetchedAt = Date()
            for page in result.pages {
                pageLastSeen[page.path] = fetchedAt
            }
            let visible = result.pages.filter { !hiddenPagePaths.contains($0.path) }
            let existingPaths = Set(pages.map(\.path))
            pages.append(contentsOf: visible.filter { !existingPaths.contains($0.path) })
            totalPageCount = result.total
            nextOffset += result.pages.count
            hasMorePages = !result.pages.isEmpty && nextOffset < totalPageCount
            saveAdditionalCachedPages(result.pages, total: result.total)
        } catch {
            guard generation == requestGeneration,
                  requestOrigin == sessionController.currentOrigin,
                  requestToken == sessionController.accessToken,
                  !Task.isCancelled
            else { return }
            if sessionController.handleAuthenticationFailure(error) {
                drafts = draftStore.loadAll(origin: sessionController.currentOrigin,
                                            accountFingerprint: sessionController.accountFingerprint)
                    .filter { !$0.isPublished }
                pages = []
                totalPageCount = 0
                nextOffset = 0
            }
            errorMessage = ErrorPresenter.message(for: error)
            canRetryError = ErrorPresenter.isRetryable(error)
            hasMorePages = false
        }
    }

    private var scopeFingerprint: String {
        TokenStore.fingerprint(
            "\(sessionController.currentOrigin)|\(sessionController.accountFingerprint)"
        )
    }

    private var scopedCachedPagesKey: String {
        "\(Self.cachedPagesKey).\(scopeFingerprint)"
    }

    private var scopedHiddenPagesKey: String {
        "\(Self.hiddenPagesKey).\(scopeFingerprint)"
    }

    private func loadCachedPageList() -> PageList? {
        guard let data = UserDefaults.standard.data(forKey: scopedCachedPagesKey),
              let cached = try? JSONDecoder().decode(PageList.self, from: data)
        else {
            return nil
        }
        return cached
    }

    private func saveCachedPageList(_ pageList: PageList) {
        guard let data = try? JSONEncoder().encode(pageList) else { return }
        UserDefaults.standard.set(data, forKey: scopedCachedPagesKey)
    }

    private func saveAdditionalCachedPages(_ additionalPages: [Page], total: Int) {
        var combined = loadCachedPageList()?.pages ?? []
        let existingPaths = Set(combined.map(\.path))
        combined.append(contentsOf: additionalPages.filter { !existingPaths.contains($0.path) })
        saveCachedPageList(PageList(totalCount: total, pages: combined))
    }

    private func pageService() throws -> PageService {
        PageService(client: try sessionController.validatedClient())
    }

    private func openPage(_ page: Page) {
        // Generate the destination's draft identity before navigation so view recreation
        // cannot create a second local draft for the same editing session.
        let draftID = draftStore.loadUnpublished(
            pagePath: page.path,
            origin: sessionController.currentOrigin,
            accountFingerprint: sessionController.accountFingerprint
        )?.id ?? UUID()
        path.append(.page(page, draftID: draftID))
    }

    private func createDraftAndOpen() {
        do {
            let id = try draftStore.createDraft(
                origin: sessionController.currentOrigin,
                accountFingerprint: sessionController.accountFingerprint
            )
            drafts = draftStore.loadAll(
                origin: sessionController.currentOrigin,
                accountFingerprint: sessionController.accountFingerprint
            ).filter { !$0.isPublished }
            path.append(.draft(id))
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    private func deleteDraft(_ draft: Draft) {
        guard draftStore.delete(id: draft.id) else {
            if let error = draftStore.lastSaveError {
                errorMessage = "草稿删除失败：\(ErrorPresenter.message(for: error))"
            }
            return
        }
        drafts.removeAll { $0.id == draft.id }
    }

    private func hidePage(_ page: Page) {
        hiddenPagePaths.insert(page.path)
        UserDefaults.standard.set(Array(hiddenPagePaths), forKey: scopedHiddenPagesKey)
        pages.removeAll { $0.path == page.path }
    }

    private func upsertPublishedPage(_ page: Page) {
        drafts.removeAll { $0.pagePath == page.path || $0.isPublished }
        let now = Date()
        pageLastSeen[page.path] = now
        if hiddenPagePaths.contains(page.path) {
            hiddenPagePaths.remove(page.path)
            UserDefaults.standard.set(Array(hiddenPagePaths), forKey: scopedHiddenPagesKey)
        }
        if let index = pages.firstIndex(where: { $0.path == page.path }) {
            pages[index] = page
        } else {
            pages.insert(page, at: 0)
            totalPageCount = max(totalPageCount, pages.count)
        }
        let cachedPages = loadCachedPageList()?.pages ?? []
        let withoutPage = cachedPages.filter { $0.path != page.path }
        saveCachedPageList(PageList(totalCount: max(totalPageCount, withoutPage.count + 1), pages: [page] + withoutPage))
    }
}

private struct DraftRowView: View {
    let draft: Draft

    var body: some View {
        AppGlassCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: draft.isPublished ? "checkmark.circle" : "pencil.and.outline")
                        .foregroundStyle(Color.brand600)
                    Text(draft.title.isEmpty ? "无标题" : draft.title)
                        .font(.headline)
                        .lineLimit(2)
                }
                HStack {
                    Text(draft.isPublished ? "已发布" : "未发布")
                    Spacer()
                    Text(SuzuriTimeLabel.string(from: draft.updatedAt))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}

private struct PageRowView: View {
    let page: Page
    let lastSeen: Date?

    var body: some View {
        AppGlassCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text(page.title.isEmpty ? "无标题" : page.title)
                    .font(.headline)
                    .lineLimit(2)

                Text(page.description.isEmpty ? "暂无摘要" : page.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 12) {
                    Label("\(page.views)", systemImage: "eye")
                        .monospacedDigit()
                    Text("Telegraph")
                    Spacer()
                    Image(systemName: page.canEdit ? "pencil" : "lock")
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview("Empty") {
    PageListView()
}
