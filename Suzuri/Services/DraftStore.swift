import Foundation
import SwiftData

/// SwiftData 草稿仓库。
@MainActor
final class DraftStore {
    let container: ModelContainer

    private let modelContext: ModelContext
    private var debounceTasks: [UUID: Task<Void, Never>] = [:]
    private var pendingSaves: [UUID: DraftSnapshot] = [:]

    private struct DraftSnapshot {
        let title: String
        let blocks: [Block]
    }

    /// 仅用于验证防抖行为，不参与持久化。
    private(set) var saveCount: Int = 0

    init(inMemory: Bool = false) {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        do {
            self.container = try ModelContainer(
                for: Draft.self,
                configurations: configuration
            )
        } catch {
            fatalError("Unable to create Draft model container: \(error)")
        }
        self.modelContext = container.mainContext
    }

    init(container: ModelContainer) {
        self.container = container
        self.modelContext = container.mainContext
    }

    /// 保存草稿；同一个 id 会更新已有实体而不是插入重复记录。
    func saveNow(id: UUID, title: String, blocks: [Block]) throws {
        debounceTasks[id]?.cancel()
        debounceTasks[id] = nil
        pendingSaves[id] = nil
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
        draft.updatedAt = .now
        try modelContext.save()
        saveCount += 1
    }

    /// 1 秒防抖保存；连续编辑只保留最后一次快照。
    func scheduleSave(id: UUID, title: String, blocks: [Block]) {
        let snapshot = DraftSnapshot(title: title, blocks: blocks)
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
                  pending.blocks == snapshot.blocks
            else { return }
            try? self.saveNow(id: id, title: snapshot.title, blocks: snapshot.blocks)
            self.debounceTasks[id] = nil
        }
    }

    func load(id: UUID) -> Draft? {
        try? fetchDraft(id: id)
    }

    /// 返回所有草稿，最新修改的排在前面。
    func loadAll() -> [Draft] {
        (try? modelContext.fetch(FetchDescriptor<Draft>()))?
            .sorted { $0.updatedAt > $1.updatedAt } ?? []
    }

    /// Compatibility alias for list screens.
    func drafts() -> [Draft] {
        loadAll()
    }

    /// Finds the latest local draft associated with a remote page path.
    func load(pagePath: String) -> Draft? {
        loadAll().first { $0.pagePath == pagePath }
    }

    /// Finds only an unpublished local revision for a remote page.
    func loadUnpublished(pagePath: String) -> Draft? {
        loadAll().first { $0.pagePath == pagePath && !$0.isPublished }
    }

    /// 创建一个新的空草稿并返回其 id。
    @discardableResult
    func createDraft(title: String = "", blocks: [Block] = [.emptyParagraph()]) throws -> UUID {
        let id = UUID()
        try saveNow(id: id, title: title, blocks: blocks)
        return id
    }

    func markPublished(id: UUID, pagePath: String) {
        debounceTasks[id]?.cancel()
        debounceTasks[id] = nil
        pendingSaves[id] = nil
        guard let draft = load(id: id) else { return }
        draft.isPublished = true
        draft.pagePath = pagePath
        try? modelContext.save()
    }

    /// 为编辑已发布页的本地草稿记录远端 path。
    func setPagePath(id: UUID, pagePath: String?) {
        guard let draft = load(id: id) else { return }
        draft.pagePath = pagePath
        try? modelContext.save()
    }

    func delete(id: UUID) {
        debounceTasks[id]?.cancel()
        debounceTasks[id] = nil
        guard let draft = load(id: id) else { return }
        modelContext.delete(draft)
        try? modelContext.save()
    }

    /// Flushes all pending snapshots before the app enters the background.
    func savePendingNow() {
        for task in debounceTasks.values {
            task.cancel()
        }
        let snapshots = pendingSaves
        debounceTasks.removeAll()
        pendingSaves.removeAll()
        for (id, snapshot) in snapshots {
            try? saveNow(id: id, title: snapshot.title, blocks: snapshot.blocks)
        }
    }

    private func fetchDraft(id: UUID) throws -> Draft? {
        let drafts = try modelContext.fetch(FetchDescriptor<Draft>())
        return drafts.first { $0.id == id }
    }
}
