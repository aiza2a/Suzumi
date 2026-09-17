import CryptoKit
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

    init(
        sessionController: SessionController = SessionController(),
        draftStore: DraftStore = DraftStore()
    ) {
        self._sessionController = State(initialValue: sessionController)
        self.draftStore = draftStore
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .top) {
                AppBackground()

                ScrollView {
                    LazyVStack(spacing: 12) {
                        ReachabilityBanner(isConnected: reachability.isConnected)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if sessionController.isAnonymous {
                            Label("未登录，首次发布时会自动创建账号", systemImage: "person.crop.circle.badge.questionmark")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .appGlass(cornerRadius: 16, allowsShadow: false)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                        }

                        if !drafts.isEmpty {
                            sectionHeader("草稿")
                            ForEach(drafts, id: \.id) { draft in
                                DraftRowView(draft: draft)
                                    .padding(.horizontal, 16)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        path.append(.draft(draft.id))
                                    }
                                    .contextMenu {
                                        Button("编辑", systemImage: "pencil") {
                                            path.append(.draft(draft.id))
                                        }
                                        Button("本地删除", systemImage: "trash", role: .destructive) {
                                            deleteDraft(draft)
                                        }
                                    }
                            }
                        }

                        if !pages.isEmpty {
                            sectionHeader("已发布")
                            ForEach(pages) { page in
                                PageRowView(page: page, lastSeen: pageLastSeen[page.path])
                                    .padding(.horizontal, 16)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        openPage(page)
                                    }
                                    .contextMenu {
                                        Button("编辑", systemImage: "pencil") {
                                            openPage(page)
                                        }
                                        Button("复制链接", systemImage: "link") {
                                            UIPasteboard.general.string = page.url
                                        }
                                        Button("本地删除", systemImage: "trash", role: .destructive) {
                                            hidePage(page)
                                        }
                                    }
                            }
                        }

                        if hasMorePages && !isLoading {
                            ProgressView("加载更多…")
                                .padding(.vertical, 12)
                                .onAppear {
                                    Task { @MainActor in await loadMoreIfNeeded() }
                                }
                        }

                        if isLoading || isInitialLoading {
                            ProgressView("加载中…")
                                .padding(.top, 48)
                        } else if drafts.isEmpty && pages.isEmpty {
                            EmptyStateView(
                                systemImage: "doc.text",
                                title: "还没有文章",
                                message: "在编辑器写下第一篇，发布后会出现在这里。"
                            )
                            .frame(minHeight: 360)
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
                .refreshable {
                    await reload()
                }
            }
            .navigationTitle("文章")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        SettingsView(sessionController: sessionController)
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("设置")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        createDraftAndOpen()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("新建文章")
                }
            }
            .navigationDestination(for: Destination.self) { destination in
                switch destination {
                case .draft(let id):
                    EditorScreen(draftID: id, sessionController: sessionController, draftStore: draftStore)
                case .page(let page, let draftID):
                    EditorScreen(
                        draftID: draftID,
                        page: page,
                        sessionController: sessionController,
                        draftStore: draftStore
                    )
                }
            }
            .task {
                guard !hasLoaded else { return }
                hasLoaded = true
                isInitialLoading = true
                await sessionController.load()
                await reload()
                isInitialLoading = false
            }
            .onAppear {
                guard hasLoaded, !isInitialLoading, !isLoading else { return }
                Task { @MainActor in await reload() }
            }
            .onChange(of: reachability.isConnected) { wasConnected, isConnected in
                guard !wasConnected, isConnected else { return }
                Task { @MainActor in await reload() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .pageDidPublish)) { notification in
                guard let page = notification.object as? Page else { return }
                upsertPublishedPage(page)
            }
            .alert("加载失败", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                if canRetryError {
                    Button("重试") {
                        Task { @MainActor in await reload() }
                    }
                }
                Button("好", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.title3.weight(.semibold))
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .accessibilityAddTraits(.isHeader)
    }

    private func reload() async {
        guard !Task.isCancelled else { return }
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

        hiddenPagePaths = Set(UserDefaults.standard.stringArray(forKey: scopedHiddenPagesKey) ?? [])
        drafts = draftStore.loadAll().filter { !$0.isPublished }

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
            guard generation == requestGeneration, !Task.isCancelled else { return }
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
            guard generation == requestGeneration, !Task.isCancelled else { return }
            if sessionController.handleAuthenticationFailure(error) {
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
        guard !isLoading,
              sessionController.accessToken != nil,
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
            guard generation == requestGeneration, !Task.isCancelled else { return }
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
            guard generation == requestGeneration, !Task.isCancelled else { return }
            if sessionController.handleAuthenticationFailure(error) {
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
        let scope = "\(sessionController.serverManager.apiBase)|\(sessionController.accessToken ?? "anonymous")"
        return SHA256.hash(data: Data(scope.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
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
        var pages = cached.pages
        for index in pages.indices {
            // A cached list came from a response that included the list permission field.
            pages[index].hasCanEditField = true
        }
        return PageList(totalCount: cached.totalCount, pages: pages)
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
        let draftID = draftStore.loadUnpublished(pagePath: page.path)?.id ?? UUID()
        path.append(.page(page, draftID: draftID))
    }

    private func createDraftAndOpen() {
        do {
            let id = try draftStore.createDraft()
            drafts = draftStore.loadAll().filter { !$0.isPublished }
            path.append(.draft(id))
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    private func deleteDraft(_ draft: Draft) {
        draftStore.delete(id: draft.id)
        drafts.removeAll { $0.id == draft.id }
    }

    private func hidePage(_ page: Page) {
        hiddenPagePaths.insert(page.path)
        UserDefaults.standard.set(Array(hiddenPagePaths), forKey: scopedHiddenPagesKey)
        pages.removeAll { $0.path == page.path }
    }

    private func upsertPublishedPage(_ page: Page) {
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
                    Text(draft.updatedAt, style: .relative)
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
                    Text(lastSeen ?? Date(), style: .relative)
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
