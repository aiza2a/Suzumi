import XCTest
import SwiftData
@testable import Suzuri

@MainActor
final class DraftStoreTests: XCTestCase {
    func testSaveRejectsScopeChangeWithoutOverwritingContentOrPendingEdits() throws {
        let store = DraftStore(inMemory: true)
        let origin = "https://api.telegra.ph"
        let id = try store.createDraft(title: "Original", origin: origin, accountFingerprint: "owner")
        store.scheduleSave(id: id, title: "Pending owner edit", blocks: [.emptyParagraph()],
                           origin: origin, accountFingerprint: "owner")
        let invalidScopes: [(String?, String?)] = [
            (origin, TokenStore.fingerprint("anonymous")),
            ("https://api.graph.org", "owner"),
            (nil, nil)
        ]
        for (invalidOrigin, invalidAccount) in invalidScopes {
            XCTAssertThrowsError(try store.saveNow(id: id, title: "Wrong account", blocks: [.emptyParagraph()],
                                                  origin: invalidOrigin, accountFingerprint: invalidAccount)) {
                XCTAssertEqual($0 as? DraftStore.DraftStoreError, .scopeMismatch)
            }
            XCTAssertEqual(store.load(id: id)?.title, "Original")
            XCTAssertEqual(store.load(id: id)?.origin, origin)
            XCTAssertEqual(store.load(id: id)?.accountFingerprint, "owner")
        }
        XCTAssertTrue(store.savePendingNow())
        XCTAssertEqual(store.load(id: id)?.title, "Pending owner edit")
    }

    func testOpenFailureIsVisibleAndPendingContentSurvivesRetry() throws {
        var canOpen = false
        let store = DraftStore(makeContainer: {
            guard canOpen else { throw CocoaError(.fileReadCorruptFile) }
            return try ModelContainer(for: Draft.self,
                                      configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        })
        XCTAssertFalse(store.isAvailable)
        XCTAssertNotNil(store.initializationError)
        XCTAssertNil(store.container)
        let id = UUID()
        XCTAssertThrowsError(try store.saveNow(id: id, title: "Keep this", blocks: [.emptyParagraph()]))
        XCTAssertEqual(store.saveCount, 0)
        XCTAssertNil(store.load(id: id))
        XCTAssertNotNil(store.lastReadError)
        canOpen = true
        XCTAssertTrue(store.retryOpeningStore())
        XCTAssertTrue(store.savePendingNow())
        XCTAssertEqual(store.load(id: id)?.title, "Keep this")
    }

    func testAdoptionIncludesAllUnboundAnonymousDraftsButNoOtherScope() throws {
        let store = DraftStore(inMemory: true)
        let origin = "https://api.telegra.ph"
        let anonymous = TokenStore.fingerprint("anonymous")
        let first = try store.createDraft(origin: origin, accountFingerprint: anonymous)
        let second = try store.createDraft(origin: origin, accountFingerprint: anonymous)
        let other = try store.createDraft(origin: "https://api.graph.org", accountFingerprint: anonymous)
        let owned = try store.createDraft(origin: origin, accountFingerprint: "other-account")
        let linked = try store.createDraft(origin: origin, accountFingerprint: anonymous)
        XCTAssertTrue(store.setPagePath(id: linked, pagePath: "existing-page"))
        store.scheduleSave(id: first, title: "Latest unsaved edit", blocks: [.emptyParagraph()],
                           origin: origin, accountFingerprint: anonymous)
        XCTAssertEqual(try store.adoptAnonymousDrafts(origin: origin, accountFingerprint: "new-account"), 2)
        XCTAssertEqual(try store.adoptAnonymousDrafts(origin: origin, accountFingerprint: "new-account"), 0)
        XCTAssertEqual(store.load(id: first)?.accountFingerprint, "new-account")
        XCTAssertEqual(store.load(id: first)?.title, "Latest unsaved edit")
        XCTAssertEqual(store.load(id: second)?.accountFingerprint, "new-account")
        XCTAssertEqual(store.load(id: other)?.accountFingerprint, anonymous)
        XCTAssertEqual(store.load(id: owned)?.accountFingerprint, "other-account")
        XCTAssertEqual(store.load(id: linked)?.accountFingerprint, anonymous)
    }

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

    func testDraftScopeFiltersAcrossOriginsAndAccounts() throws {
        let store = DraftStore(inMemory: true)
        let id = UUID()
        try store.saveNow(
            id: id,
            title: "隔离草稿",
            blocks: [.emptyParagraph()],
            origin: "https://api.telegra.ph",
            accountFingerprint: "account-a"
        )

        XCTAssertEqual(
            store.loadAll(origin: "https://api.telegra.ph", accountFingerprint: "account-a").count,
            1
        )
        XCTAssertTrue(
            store.loadAll(origin: "https://api.graph.org", accountFingerprint: "account-a").isEmpty
        )
        XCTAssertTrue(
            store.loadAll(origin: "https://api.telegra.ph", accountFingerprint: "account-b").isEmpty
        )
        XCTAssertEqual(store.load(id: id)?.origin, "https://api.telegra.ph")
        XCTAssertNil(store.lastSaveError)
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
