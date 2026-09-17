import XCTest
@testable import Suzuri

@MainActor
final class BlockEditorDocumentTests: XCTestCase {
    func testDocumentStartsWithOneEmptyParagraph() {
        let document = BlockEditorDocument()
        XCTAssertEqual(document.blocks.count, 1)
        XCTAssertTrue(document.blocks[0].isEmpty)
        guard case .paragraph = document.blocks[0] else {
            return XCTFail("Expected paragraph")
        }
    }

    func testLookupFindsIndexAndBlock() {
        let firstID = UUID()
        let secondID = UUID()
        let first = Block.paragraph(id: firstID, text: "first")
        let second = Block.quote(id: secondID, text: "second")
        let document = BlockEditorDocument(blocks: [first, second])
        XCTAssertEqual(document.index(of: secondID), 1)
        XCTAssertEqual(document.block(for: firstID), first)
        XCTAssertNil(document.index(of: UUID()))
    }

    func testInsertAfterAndAtClamp() {
        let first = Block.paragraph(id: UUID(), text: "first")
        let second = Block.paragraph(id: UUID(), text: "second")
        let document = BlockEditorDocument(blocks: [first])
        document.insertBlock(second, after: first.id)
        XCTAssertEqual(document.blocks.map(\.id), [first.id, second.id])

        let beginning = Block.paragraph(id: UUID(), text: "beginning")
        let ending = Block.paragraph(id: UUID(), text: "ending")
        document.insertBlock(beginning, at: -10)
        document.insertBlock(ending, at: 100)
        XCTAssertEqual(document.blocks.first?.id, beginning.id)
        XCTAssertEqual(document.blocks.last?.id, ending.id)
    }

    func testRemoveLastBlockRestoresEmptyParagraph() {
        let only = Block.paragraph(id: UUID(), text: "only")
        let document = BlockEditorDocument(blocks: [only])
        XCTAssertEqual(document.removeBlock(id: only.id), 0)
        XCTAssertEqual(document.blocks.count, 1)
        XCTAssertTrue(document.blocks[0].isEmpty)
    }

    func testRemoveBlocksReturnsFirstRemovedIndex() {
        let blocks = (0..<4).map { Block.paragraph(id: UUID(), text: "\($0)") }
        let document = BlockEditorDocument(blocks: blocks)
        let selected = Set([blocks[1].id, blocks[3].id])
        XCTAssertEqual(document.removeBlocks(ids: selected), 1)
        XCTAssertEqual(document.blocks.map(\.textContent), ["0", "2"])
    }

    func testRemoveBlocksAllRestoresEmptyParagraph() {
        let blocks = (0..<3).map { Block.paragraph(id: UUID(), text: "\($0)") }
        let document = BlockEditorDocument(blocks: blocks)
        XCTAssertEqual(document.removeBlocks(ids: Set(blocks.map(\.id))), 0)
        XCTAssertEqual(document.blocks.count, 1)
        XCTAssertTrue(document.blocks[0].isEmpty)
    }

    func testReplaceBlock() {
        let id = UUID()
        let document = BlockEditorDocument(blocks: [.paragraph(id: id, text: "old")])
        let replacement = Block.heading(id: id, level: 1, text: "new")
        document.replaceBlock(id: id, with: replacement)
        XCTAssertEqual(document.blocks, [replacement])
    }

    func testMoveBlockAdjustsDestinationAfterRemoval() {
        let blocks = (0..<4).map { Block.paragraph(id: UUID(), text: "\($0)") }
        let document = BlockEditorDocument(blocks: blocks)
        document.moveBlock(from: 0, to: 4)
        XCTAssertEqual(document.blocks.map(\.textContent), ["1", "2", "3", "0"])
        document.moveBlock(from: 3, to: 0)
        XCTAssertEqual(document.blocks.map(\.textContent), ["0", "1", "2", "3"])
    }

    func testMoveSelectedBlocksRejectsNonContiguousSelection() {
        let blocks = (0..<4).map { Block.paragraph(id: UUID(), text: "\($0)") }
        let document = BlockEditorDocument(blocks: blocks)
        let selected = Set([blocks[0].id, blocks[2].id])
        document.moveSelectedBlocks(selected, direction: .down)
        XCTAssertEqual(document.blocks.map(\.textContent), ["0", "1", "2", "3"])
    }

    func testMoveSelectedBlocksUpMovesAContiguousRun() {
        let blocks = (0..<4).map { Block.paragraph(id: UUID(), text: "\($0)") }
        let document = BlockEditorDocument(blocks: blocks)
        let selected = Set([blocks[1].id, blocks[2].id])
        document.moveSelectedBlocks(selected, direction: .up)
        XCTAssertEqual(document.blocks.map(\.textContent), ["1", "2", "0", "3"])
    }

    func testUpdateTextChangesOnlyTextContent() {
        let id = UUID()
        let document = BlockEditorDocument(blocks: [.heading(id: id, level: 2, text: "old")])
        document.updateText(blockID: id, text: "new")
        guard case let .heading(updatedID, level, text) = document.blocks[0] else {
            return XCTFail("Expected heading")
        }
        XCTAssertEqual(updatedID, id)
        XCTAssertEqual(level, 2)
        XCTAssertEqual(text, "new")
    }

    func testSplitBlockAtBeginningAndEnd() throws {
        let firstID = UUID()
        let document = BlockEditorDocument(blocks: [.paragraph(id: firstID, text: "abc")])
        let beginningID = try XCTUnwrap(document.splitBlock(id: firstID, atOffset: 0))
        XCTAssertEqual(document.blocks[0].textContent, "")
        XCTAssertEqual(document.blocks[1].textContent, "abc")
        XCTAssertEqual(document.blocks[1].id, beginningID)

        let endID = try XCTUnwrap(document.splitBlock(id: beginningID, atOffset: 3))
        XCTAssertEqual(document.blocks[1].textContent, "abc")
        XCTAssertEqual(document.blocks[2].textContent, "")
        XCTAssertEqual(document.blocks[2].id, endID)
    }

    func testSplitNonTextBlockReturnsNil() {
        let divider = Block.newDivider()
        let document = BlockEditorDocument(blocks: [divider])
        XCTAssertNil(document.splitBlock(id: divider.id, atOffset: 0))
        XCTAssertEqual(document.blocks, [divider])
    }

    func testSplitBlockClampsNegativeAndOverlongOffsets() throws {
        let negativeID = UUID()
        let negativeDocument = BlockEditorDocument(
            blocks: [.paragraph(id: negativeID, text: "abc")]
        )
        let negativeSplitID = try XCTUnwrap(
            negativeDocument.splitBlock(id: negativeID, atOffset: -1)
        )
        XCTAssertEqual(negativeDocument.blocks[0].textContent, "")
        XCTAssertEqual(negativeDocument.block(for: negativeSplitID)?.textContent, "abc")

        let overlongID = UUID()
        let overlongDocument = BlockEditorDocument(
            blocks: [.paragraph(id: overlongID, text: "abc")]
        )
        let overlongSplitID = try XCTUnwrap(
            overlongDocument.splitBlock(id: overlongID, atOffset: 100)
        )
        XCTAssertEqual(overlongDocument.blocks[0].textContent, "abc")
        XCTAssertEqual(overlongDocument.block(for: overlongSplitID)?.textContent, "")
    }

    func testMergeWithPreviousReturnsCursorOffset() {
        let firstID = UUID()
        let secondID = UUID()
        let document = BlockEditorDocument(blocks: [
            .paragraph(id: firstID, text: "abc"),
            .paragraph(id: secondID, text: "def")
        ])
        let result = document.mergeWithPrevious(id: secondID)
        XCTAssertEqual(result?.blockID, firstID)
        XCTAssertEqual(result?.cursorOffset, 3)
        XCTAssertEqual(document.blocks, [.paragraph(id: firstID, text: "abcdef")])
    }

    func testMergeRejectsFirstOrNonTextPreviousBlock() {
        let first = Block.newDivider()
        let second = Block.paragraph(id: UUID(), text: "text")
        let document = BlockEditorDocument(blocks: [first, second])
        XCTAssertNil(document.mergeWithPrevious(id: first.id))
        XCTAssertNil(document.mergeWithPrevious(id: second.id))
        XCTAssertEqual(document.blocks.count, 2)
    }

    func testMergeWithNextAppendsTextAndRemovesNextBlock() {
        let firstID = UUID()
        let secondID = UUID()
        let document = BlockEditorDocument(blocks: [
            .paragraph(id: firstID, text: "abc"),
            .paragraph(id: secondID, text: "def")
        ])

        XCTAssertTrue(document.mergeWithNext(id: firstID))
        XCTAssertEqual(document.blocks.count, 1)
        XCTAssertEqual(document.blocks[0], .paragraph(id: firstID, text: "abcdef"))
        XCTAssertNil(document.block(for: secondID))
    }

    func testMergeWithNextReturnsFalseWhenThereIsNoNextBlock() {
        let first = Block.paragraph(id: UUID(), text: "only")
        let document = BlockEditorDocument(blocks: [first])

        XCTAssertFalse(document.mergeWithNext(id: first.id))
        XCTAssertEqual(document.blocks, [first])
    }

    func testMergeWithNextRejectsNonTextNextBlock() {
        let first = Block.paragraph(id: UUID(), text: "text")
        let next = Block.newDivider()
        let document = BlockEditorDocument(blocks: [first, next])

        XCTAssertFalse(document.mergeWithNext(id: first.id))
        XCTAssertEqual(document.blocks, [first, next])
    }

    func testAddListItemAppendsOrInsertsAfterItem() throws {
        let list = Block.emptyBulletList()
        let document = BlockEditorDocument(blocks: [list])
        let firstItemID = try XCTUnwrap(document.blocks[0].listItemIDs.first)
        document.addListItem(to: list.id, after: firstItemID)
        document.addListItem(to: list.id, after: nil)
        guard case let .bulletList(_, items) = document.blocks[0] else {
            return XCTFail("Expected bullet list")
        }
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[1].text, "")
    }

    func testSplitListItem() throws {
        let itemID = UUID()
        let listID = UUID()
        let document = BlockEditorDocument(blocks: [
            .numberedList(id: listID, items: [ListItem(id: itemID, text: "abcd")])
        ])
        let newItemID = try XCTUnwrap(
            document.splitListItem(blockID: listID, itemID: itemID, atOffset: 2)
        )
        guard case let .numberedList(_, items) = document.blocks[0] else {
            return XCTFail("Expected numbered list")
        }
        XCTAssertEqual(items.map(\.text), ["ab", "cd"])
        XCTAssertEqual(items[1].id, newItemID)
    }

    func testDeleteLastListItemCreatesParagraph() throws {
        let list = Block.emptyNumberedList()
        let document = BlockEditorDocument(blocks: [list])
        let itemID = try XCTUnwrap(document.blocks[0].listItemIDs.first)
        document.deleteListItem(in: list.id, at: itemID)
        guard case .paragraph = document.blocks[0] else {
            return XCTFail("Expected fallback paragraph")
        }
    }
}

private extension Block {
    var listItemIDs: [UUID] {
        switch self {
        case let .bulletList(_, items), let .numberedList(_, items):
            items.map(\.id)
        default:
            []
        }
    }
}
