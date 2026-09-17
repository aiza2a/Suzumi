import XCTest
@testable import Suzuri

@MainActor
final class DraftStoreTests: XCTestCase {
    func testSaveAndLoadPreservesDraftContent() throws {
        let store = DraftStore(inMemory: true)
        let id = UUID()
        let blocks: [Block] = [
            .paragraph(id: UUID(), text: "草稿正文"),
            .figure(id: UUID(), imageURL: URL(string: "https://cdn.example/a.jpg"), caption: "图")
        ]

        try store.saveNow(id: id, title: "草稿标题", blocks: blocks)

        let draft = try XCTUnwrap(store.load(id: id))
        XCTAssertEqual(draft.id, id)
        XCTAssertEqual(draft.title, "草稿标题")
        XCTAssertFalse(draft.isPublished)
        XCTAssertEqual(try JSONDecoder().decode([Block].self, from: draft.blocksData), blocks)
    }

    func testSaveNowUpdatesExistingEntityInsteadOfDuplicating() throws {
        let store = DraftStore(inMemory: true)
        let id = UUID()
        try store.saveNow(id: id, title: "旧标题", blocks: [.emptyParagraph()])
        try store.saveNow(id: id, title: "新标题", blocks: [.paragraph(id: UUID(), text: "新内容")])

        XCTAssertEqual(store.loadAll().count, 1)
        XCTAssertEqual(store.load(id: id)?.title, "新标题")
    }

    func testDebounceMergesConsecutiveSaves() async throws {
        let store = DraftStore(inMemory: true)
        let id = UUID()
        store.scheduleSave(id: id, title: "第一版", blocks: [.paragraph(id: UUID(), text: "a")])
        try await Task.sleep(nanoseconds: 250_000_000)
        store.scheduleSave(id: id, title: "最后版", blocks: [.paragraph(id: UUID(), text: "b")])

        try await Task.sleep(nanoseconds: 1_150_000_000)

        XCTAssertEqual(store.saveCount, 1)
        XCTAssertEqual(store.load(id: id)?.title, "最后版")
    }

    func testMarkPublishedSetsStateAndPath() throws {
        let store = DraftStore(inMemory: true)
        let id = try store.createDraft()

        store.markPublished(id: id, pagePath: "published-path")

        let draft = try XCTUnwrap(store.load(id: id))
        XCTAssertTrue(draft.isPublished)
        XCTAssertEqual(draft.pagePath, "published-path")
    }

    func testDeleteRemovesOnlyLocalDraft() throws {
        let store = DraftStore(inMemory: true)
        let first = try store.createDraft(title: "第一篇")
        let second = try store.createDraft(title: "第二篇")

        store.delete(id: first)

        XCTAssertNil(store.load(id: first))
        XCTAssertEqual(store.load(id: second)?.title, "第二篇")
    }

    func testSavingAnEditReopensAPublishedDraft() throws {
        let store = DraftStore(inMemory: true)
        let id = try store.createDraft(title: "已发布")
        store.markPublished(id: id, pagePath: "page-path")

        try store.saveNow(
            id: id,
            title: "已修改",
            blocks: [.paragraph(id: UUID(), text: "新版本")]
        )

        XCTAssertFalse(try XCTUnwrap(store.load(id: id)).isPublished)
        XCTAssertEqual(store.loadUnpublished(pagePath: "page-path")?.id, id)
    }

    func testDeleteClearsPendingDebouncedSnapshot() async throws {
        let store = DraftStore(inMemory: true)
        let id = UUID()
        store.scheduleSave(
            id: id,
            title: "即将删除",
            blocks: [.paragraph(id: UUID(), text: "内容")]
        )
        store.delete(id: id)
        store.savePendingNow()
        try await Task.sleep(nanoseconds: 1_100_000_000)

        XCTAssertNil(store.load(id: id))
        XCTAssertEqual(store.saveCount, 0)
    }
}
