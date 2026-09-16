import XCTest
@testable import Suzuri

final class BlockTests: XCTestCase {
    func testEmptyTextBlocksAreEmpty() {
        XCTAssertTrue(Block.emptyParagraph().isEmpty)
        XCTAssertTrue(Block.emptyHeading().isEmpty)
        XCTAssertTrue(Block.emptyQuote().isEmpty)
        XCTAssertTrue(Block.emptyCode().isEmpty)
        XCTAssertTrue(Block.emptyLink().isEmpty)
    }

    func testNonEmptyTextBlocksAreNotEmpty() {
        let id = UUID()
        XCTAssertFalse(Block.paragraph(id: id, text: "text").isEmpty)
        XCTAssertFalse(Block.heading(id: id, level: 1, text: "title").isEmpty)
        XCTAssertFalse(Block.quote(id: id, text: "quote").isEmpty)
        XCTAssertFalse(Block.code(id: id, text: "let x = 1").isEmpty)
        XCTAssertFalse(Block.link(id: id, text: "site", url: exampleURL).isEmpty)
    }

    func testEmptyListsContainBlankItems() {
        XCTAssertTrue(Block.emptyBulletList().isEmpty)
        XCTAssertTrue(Block.emptyNumberedList().isEmpty)
        XCTAssertFalse(Block.bulletList(id: UUID(), items: [ListItem(text: "item")]).isEmpty)
        XCTAssertFalse(Block.numberedList(id: UUID(), items: [ListItem(text: "item")]).isEmpty)
    }

    func testDividerIsStructuralAndNotEmpty() {
        XCTAssertFalse(Block.newDivider().isEmpty)
    }

    func testFigureIsEmptyWithoutImageOrCaption() {
        XCTAssertTrue(Block.emptyFigure().isEmpty)
        XCTAssertFalse(
            Block.figure(id: UUID(), imageURL: exampleURL, caption: "").isEmpty
        )
        XCTAssertFalse(
            Block.figure(id: UUID(), imageURL: nil, caption: "caption").isEmpty
        )
    }

    func testTextContentReadsAllTextBlockKinds() {
        let id = UUID()
        XCTAssertEqual(Block.paragraph(id: id, text: "p").textContent, "p")
        XCTAssertEqual(Block.heading(id: id, level: 2, text: "h").textContent, "h")
        XCTAssertEqual(Block.quote(id: id, text: "q").textContent, "q")
        XCTAssertEqual(Block.code(id: id, text: "c").textContent, "c")
        XCTAssertEqual(Block.link(id: id, text: "l", url: exampleURL).textContent, "l")
        XCTAssertNil(Block.newDivider().textContent)
        XCTAssertNil(Block.emptyFigure().textContent)
    }

    func testTextContentSetterPreservesIdentityAndMetadata() throws {
        let id = UUID()
        let url = try XCTUnwrap(URL(string: "https://example.com/article"))
        var heading = Block.heading(id: id, level: 2, text: "old")
        heading.textContent = "new"
        XCTAssertEqual(heading.id, id)
        guard case let .heading(_, level, text) = heading else {
            return XCTFail("Expected heading")
        }
        XCTAssertEqual(level, 2)
        XCTAssertEqual(text, "new")

        var link = Block.link(id: id, text: "old", url: url)
        link.textContent = "new"
        guard case let .link(linkID, text, linkURL) = link else {
            return XCTFail("Expected link")
        }
        XCTAssertEqual(linkID, id)
        XCTAssertEqual(text, "new")
        XCTAssertEqual(linkURL, url)
    }

    func testTextContentSetterPreservesIDForParagraphQuoteAndCode() {
        let paragraphID = UUID()
        var paragraph = Block.paragraph(id: paragraphID, text: "old paragraph")
        paragraph.textContent = "new paragraph"
        guard case let .paragraph(updatedParagraphID, paragraphText) = paragraph else {
            return XCTFail("Expected paragraph")
        }
        XCTAssertEqual(updatedParagraphID, paragraphID)
        XCTAssertEqual(paragraphText, "new paragraph")

        let quoteID = UUID()
        var quote = Block.quote(id: quoteID, text: "old quote")
        quote.textContent = "new quote"
        guard case let .quote(updatedQuoteID, quoteText) = quote else {
            return XCTFail("Expected quote")
        }
        XCTAssertEqual(updatedQuoteID, quoteID)
        XCTAssertEqual(quoteText, "new quote")

        let codeID = UUID()
        var code = Block.code(id: codeID, text: "old code")
        code.textContent = "new code"
        guard case let .code(updatedCodeID, codeText) = code else {
            return XCTFail("Expected code")
        }
        XCTAssertEqual(updatedCodeID, codeID)
        XCTAssertEqual(codeText, "new code")
    }

    func testNonTextContentSetterDoesNothing() {
        let original = Block.newDivider()
        var changed = original
        changed.textContent = "ignored"
        XCTAssertEqual(changed, original)
    }

    func testListBlockClassification() {
        XCTAssertTrue(Block.emptyBulletList().isListBlock)
        XCTAssertTrue(Block.emptyNumberedList().isListBlock)
        XCTAssertFalse(Block.emptyParagraph().isListBlock)
        XCTAssertFalse(Block.emptyFigure().isListBlock)
    }

    func testFactoriesCreateExpectedKinds() {
        guard case .paragraph = Block.emptyParagraph() else { return XCTFail("paragraph") }
        guard case .heading = Block.emptyHeading(level: 2) else { return XCTFail("heading") }
        guard case .bulletList = Block.emptyBulletList() else { return XCTFail("bullet list") }
        guard case .numberedList = Block.emptyNumberedList() else { return XCTFail("numbered list") }
        guard case .quote = Block.emptyQuote() else { return XCTFail("quote") }
        guard case .code = Block.emptyCode() else { return XCTFail("code") }
        guard case .divider = Block.newDivider() else { return XCTFail("divider") }
        guard case .figure = Block.emptyFigure() else { return XCTFail("figure") }
        guard case .link = Block.emptyLink() else { return XCTFail("link") }
    }

    func testBlockTypeRegistryCreatesEveryKind() {
        XCTAssertEqual(BlockType.allCases.count, 9)
        for type in BlockType.allCases {
            XCTAssertFalse(type.displayName.isEmpty)
            XCTAssertFalse(type.icon.isEmpty)
            _ = type.makeEmpty
        }
    }

    func testBlockTypeRetainsTextForTurnInto() throws {
        let id = UUID()
        let block = BlockType.heading.makeBlock(id: id, text: "kept")
        guard case let .heading(blockID, level, text) = block else {
            return XCTFail("Expected heading")
        }
        XCTAssertEqual(blockID, id)
        XCTAssertEqual(level, 1)
        XCTAssertEqual(text, "kept")
        XCTAssertEqual(BlockType.paragraph, .text)
        _ = try XCTUnwrap(BlockType.codeBlock.makeEmptyBlock().textContent)
    }

    func testBlockTypeMakeEmptyCreatesEveryConcreteBlockKind() {
        guard case .paragraph = BlockType.text.makeEmpty else {
            return XCTFail("Expected paragraph")
        }
        guard case .heading = BlockType.heading.makeEmpty else {
            return XCTFail("Expected heading")
        }
        guard case .quote = BlockType.quote.makeEmpty else {
            return XCTFail("Expected quote")
        }
        guard case .bulletList = BlockType.bulletList.makeEmpty else {
            return XCTFail("Expected bullet list")
        }
        guard case .numberedList = BlockType.numberedList.makeEmpty else {
            return XCTFail("Expected numbered list")
        }
        guard case .code = BlockType.code.makeEmpty else {
            return XCTFail("Expected code")
        }
        guard case .divider = BlockType.divider.makeEmpty else {
            return XCTFail("Expected divider")
        }
        guard case .figure = BlockType.figure.makeEmpty else {
            return XCTFail("Expected figure")
        }
        guard case .link = BlockType.link.makeEmpty else {
            return XCTFail("Expected link")
        }
    }

    private var exampleURL: URL {
        URL(string: "https://example.com/image.jpg") ?? URL(fileURLWithPath: "/")
    }
}
