import XCTest
@testable import Suzuri

@MainActor
final class BlockEditorViewTests: XCTestCase {
    func testSelectionStartsInactiveAndSelectsOneBlock() {
        let selection = MultiBlockSelection()
        let blockID = UUID()

        XCTAssertFalse(selection.isActive)
        selection.select(blockID)

        XCTAssertTrue(selection.isActive)
        XCTAssertEqual(selection.selectedBlockIDs, Set([blockID]))
        XCTAssertEqual(selection.anchorID, blockID)
    }

    func testSelectRangeIncludesBothEndpoints() {
        let blocks = (0 ..< 4).map { _ in Block.emptyParagraph() }
        let selection = MultiBlockSelection()

        selection.selectRange(from: 1, to: 3, in: blocks)

        XCTAssertEqual(
            selection.selectedBlockIDs,
            Set(blocks[1 ... 3].map(\.id))
        )
    }

    func testSelectRangeWorksInReverseOrder() {
        let blocks = (0 ..< 4).map { _ in Block.emptyParagraph() }
        let selection = MultiBlockSelection()

        selection.selectRange(from: 3, to: 1, in: blocks)

        XCTAssertEqual(selection.selectedBlockIDs, Set(blocks[1 ... 3].map(\.id)))
    }

    func testOutOfBoundsRangeDoesNotChangeSelection() {
        let blocks = (0 ..< 2).map { _ in Block.emptyParagraph() }
        let selection = MultiBlockSelection()
        selection.select(blocks[0].id)

        selection.selectRange(from: -1, to: 1, in: blocks)

        XCTAssertEqual(selection.selectedBlockIDs, [blocks[0].id])
    }

    func testClearResetsSelectionAndAnchor() {
        let selection = MultiBlockSelection()
        let blocks = (0 ..< 3).map { _ in Block.emptyParagraph() }
        selection.selectRange(from: blocks[0].id, to: blocks[2].id, in: blocks)

        selection.clear()

        XCTAssertFalse(selection.isActive)
        XCTAssertTrue(selection.selectedBlockIDs.isEmpty)
        XCTAssertNil(selection.anchorID)
    }

    func testSelectAllIncludesEveryBlock() {
        let blocks = (0 ..< 3).map { _ in Block.emptyParagraph() }
        let selection = MultiBlockSelection()

        selection.selectAll(blocks: blocks)

        XCTAssertEqual(selection.selectedBlockIDs, Set(blocks.map(\.id)))
        XCTAssertEqual(selection.anchorID, blocks.first?.id)
    }
}
