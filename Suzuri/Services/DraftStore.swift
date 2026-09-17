import Foundation
import SwiftData

/// SwiftData 草稿仓库。
@MainActor
final class DraftStore {
    enum DraftStoreError: Error, Equatable {
        case notFound
    }

    let container: ModelContainer

    private let modelContext: ModelContext
    private var debounceTasks: [UUID: Task<Void, Never>] = [:]
    private var pendingSaves: [UUID: DraftSnapshot] = [:]

    private struct DraftSnapshot {
        let title: String
        let blocks: [Block]
        let origin: String?
        let accountFingerprint: String?
    }

    /// 仅用于验证防抖行为，不参与持久化。
    private(set) var saveCount: Int = 0
    /// The last synchronous or debounced save error, if any.
    private(set) var lastSaveError: Error?

    init(inMemory: Bool = false) {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        let resolvedContainer: ModelContainer
        do {
            resolvedContainer = try ModelContainer(
                for: Draft.self,
                configurations: configuration
            )
        } catch {
            // A damaged persistent store must not prevent the editor from launching.
            // The user can continue in memory while the next save rebuilds local state.
            let fallback = ModelConfiguration(isStoredInMemoryOnly: true)
            resolvedContainer = try! ModelContainer(
                for: Draft.self,
                configurations: fallback
            )
        }
        self.container = resolvedContainer
        self.modelContext = resolvedContainer.mainContext
        backfillLegacyScopes()
    }

    init(container: ModelContainer) {
        self.container = container
        self.modelContext = container.mainContext
        backfillLegacyScopes()
    }

    /// 保存草稿；同一个 id 会更新已有实体而不是插入重复记录。
    func saveNow(
        id: UUID,
        title: String,
        blocks: [Block],
        origin: String? = nil,
        accountFingerprint: String? = nil
    ) throws {
        debounceTasks[id]?.cancel()
        debounceTasks[id] = nil
        pendingSaves[id] = nil
        lastSaveError = nil

        do {
            let data = try JSONEncoder().encode(blocks)
            let draft: Draft
            if let existing = try fetchDraft(id: id) {
                draft = existing
            } else {
                draft = Draft(id: id)
                modelContext.insert(draft)
            }
            draft.title = title
            draft.blocksData = data
            // Saving after a published revision creates a new unpublished revision.
            draft.isPublished = false
            if let origin {
                draft.origin = origin
            }
            if let accountFingerprint {
                draft.accountFingerprint = accountFingerprint
            }
            draft.updatedAt = .now
            try modelContext.save()
            saveCount += 1
        } catch {
            lastSaveError = error
            throw error
        }
    }

    /// 1 秒防抖保存；连续编辑只保留最后一次快照。
    func scheduleSave(
        id: UUID,
        title: String,
        blocks: [Block],
        origin: String? = nil,
        accountFingerprint: String? = nil
    ) {
        let snapshot = DraftSnapshot(
            title: title,
            blocks: blocks,
            origin: origin,
            accountFingerprint: accountFingerprint
        )
        pendingSaves[id] = snapshot
        debounceTasks[id]?.cancel()
        debounceTasks[id] = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 1_000_000_000)
            } catch {
                return
            }
            guard let self, !Task.isCancelled,
                  let pending = self.pendingSaves[id],
                  pending.title == snapshot.title,
                  pending.blocks == snapshot.blocks,
                  pending.origin == snapshot.origin,
                  pending.accountFingerprint == snapshot.accountFingerprint
            else { return }
            do {
                try self.saveNow(
                    id: id,
                    title: snapshot.title,
                    blocks: snapshot.blocks,
                    origin: snapshot.origin,
                    accountFingerprint: snapshot.accountFingerprint
                )
            } catch {
                self.lastSaveError = error
            }
            self.debounceTasks[id] = nil
        }
    }

    func load(
        id: UUID,
        origin: String? = nil,
        accountFingerprint: String? = nil
    ) -> Draft? {
        do {
            guard let draft = try fetchDraft(id: id),
                  matchesScope(draft, origin: origin, accountFingerprint: accountFingerprint)
            else { return nil }
            return draft
        } catch {
            return nil
        }
    }

    /// 返回所有草稿，最新修改的排在前面。
    func loadAll(origin: String? = nil, accountFingerprint: String? = nil) -> [Draft] {
        ((try? modelContext.fetch(FetchDescriptor<Draft>())) ?? [])
            .filter { matchesScope($0, origin: origin, accountFingerprint: accountFingerprint) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Compatibility alias for list screens.
    func drafts(origin: String? = nil, accountFingerprint: String? = nil) -> [Draft] {
        loadAll(origin: origin, accountFingerprint: accountFingerprint)
    }

    /// Finds the latest local draft associated with a remote page path.
    func load(
        pagePath: String,
        origin: String? = nil,
        accountFingerprint: String? = nil
    ) -> Draft? {
        loadAll(origin: origin, accountFingerprint: accountFingerprint)
            .first { $0.pagePath == pagePath }
    }

    /// Finds only an unpublished local revision for a remote page.
    func loadUnpublished(
        pagePath: String,
        origin: String? = nil,
        accountFingerprint: String? = nil
    ) -> Draft? {
        loadAll(origin: origin, accountFingerprint: accountFingerprint)
            .first { $0.pagePath == pagePath && !$0.isPublished }
    }

    /// 创建一个新的空草稿并返回其 id。
    @discardableResult
    func createDraft(
        title: String = "",
        blocks: [Block] = [.emptyParagraph()],
        origin: String? = nil,
        accountFingerprint: String? = nil
    ) throws -> UUID {
        let id = UUID()
        try saveNow(
            id: id,
            title: title,
            blocks: blocks,
            origin: origin,
            accountFingerprint: accountFingerprint
        )
        return id
    }

    @discardableResult
    func markPublished(
        id: UUID,
        pagePath: String,
        origin: String? = nil,
        accountFingerprint: String? = nil
    ) -> Bool {
        debounceTasks[id]?.cancel()
        debounceTasks[id] = nil
        pendingSaves[id] = nil
        guard let draft = load(
            id: id,
            origin: origin,
            accountFingerprint: accountFingerprint
        ) else {
            lastSaveError = DraftStoreError.notFound
            return false
        }

        let oldPublished = draft.isPublished
        let oldPath = draft.pagePath
        draft.isPublished = true
        draft.pagePath = pagePath
        do {
            try modelContext.save()
            lastSaveError = nil
            return true
        } catch {
            draft.isPublished = oldPublished
            draft.pagePath = oldPath
            lastSaveError = error
            return false
        }
    }

    /// Moves a draft into the current authenticated scope after anonymous creation.
    /// This is intentionally addressed by UUID so only the active editor can adopt it.
    @discardableResult
    func adoptScope(id: UUID, origin: String, accountFingerprint: String) -> Bool {
        let draft: Draft
        do {
            guard let found = try fetchDraft(id: id) else {
                lastSaveError = DraftStoreError.notFound
                return false
            }
            draft = found
        } catch {
            lastSaveError = error
            return false
        }
        let oldOrigin = draft.origin
        let oldAccountFingerprint = draft.accountFingerprint
        draft.origin = origin
        draft.accountFingerprint = accountFingerprint
        do {
            try modelContext.save()
            lastSaveError = nil
            return true
        } catch {
            draft.origin = oldOrigin
            draft.accountFingerprint = oldAccountFingerprint
            lastSaveError = error
            return false
        }
    }

    /// 为编辑已发布页的本地草稿记录远端 path。
    @discardableResult
    func setPagePath(
        id: UUID,
        pagePath: String?,
        origin: String? = nil,
        accountFingerprint: String? = nil
    ) -> Bool {
        guard let draft = load(
            id: id,
            origin: origin,
            accountFingerprint: accountFingerprint
        ) else {
            lastSaveError = DraftStoreError.notFound
            return false
        }
        let oldPath = draft.pagePath
        draft.pagePath = pagePath
        do {
            try modelContext.save()
            lastSaveError = nil
            return true
        } catch {
            draft.pagePath = oldPath
            lastSaveError = error
            return false
        }
    }

    @discardableResult
    func delete(id: UUID) -> Bool {
        debounceTasks[id]?.cancel()
        debounceTasks[id] = nil
        pendingSaves[id] = nil
        guard let draft = load(id: id) else { return false }
        modelContext.delete(draft)
        do {
            try modelContext.save()
            lastSaveError = nil
            return true
        } catch {
            lastSaveError = error
            return false
        }
    }

    /// Flushes all pending snapshots before the app enters the background.
    @discardableResult
    func savePendingNow() -> Bool {
        lastSaveError = nil
        for task in debounceTasks.values {
            task.cancel()
        }
        let snapshots = pendingSaves
        debounceTasks.removeAll()
        pendingSaves.removeAll()

        var allSaved = true
        var firstError: Error?
        for (id, snapshot) in snapshots {
            do {
                try saveNow(
                    id: id,
                    title: snapshot.title,
                    blocks: snapshot.blocks,
                    origin: snapshot.origin,
                    accountFingerprint: snapshot.accountFingerprint
                )
            } catch {
                allSaved = false
                firstError = firstError ?? error
            }
        }
        if let firstError {
            lastSaveError = firstError
        }
        return allSaved
    }

    private func backfillLegacyScopes() {
        let defaultOrigin = TokenStore.origin(for: "https://api.telegra.ph")
        let tokenStore = TokenStore()
        let token = tokenStore.loadString(.accessToken, origin: defaultOrigin)
            ?? tokenStore.loadString(TokenStore.Key.accessToken.rawValue)
        let accountFingerprint = TokenStore.fingerprint(token ?? "anonymous")

        do {
            let drafts = try modelContext.fetch(FetchDescriptor<Draft>())
            var changed = false
            for draft in drafts {
                if draft.origin == nil {
                    draft.origin = defaultOrigin
                    changed = true
                }
                if draft.accountFingerprint == nil {
                    draft.accountFingerprint = accountFingerprint
                    changed = true
                }
            }
            if changed {
                try modelContext.save()
            }
        } catch {
            lastSaveError = error
        }
    }

    private func matchesScope(
        _ draft: Draft,
        origin: String?,
        accountFingerprint: String?
    ) -> Bool {
        if let origin, draft.origin != origin {
            return false
        }
        if let accountFingerprint, draft.accountFingerprint != accountFingerprint {
            return false
        }
        return true
    }

    private func fetchDraft(id: UUID) throws -> Draft? {
        let drafts = try modelContext.fetch(FetchDescriptor<Draft>())
        return drafts.first { $0.id == id }
    }
}
