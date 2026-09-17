import XCTest
@testable import Suzuri

final class BlockCodingTests: XCTestCase {
    func testParagraphAndHeadingEncodeToTelegraphTags() throws {
        let paragraph = Block.paragraph(id: UUID(), text: "body")
        let heading = Block.heading(id: UUID(), level: 1, text: "title")
        let subheading = Block.heading(id: UUID(), level: 2, text: "subtitle")
        let nodes = BlockEncoder.toNodes([paragraph, heading, subheading])
        XCTAssertEqual(nodes.map(\.tag), ["p", "h3", "h4"])
        XCTAssertEqual(text(from: nodes[0]), "body")
    }

    func testListsEncodeAsUnorderedAndOrderedListItems() throws {
        let bullet = Block.bulletList(
            id: UUID(),
            items: [ListItem(text: "one"), ListItem(text: "two")]
        )
        let numbered = Block.numberedList(id: UUID(), items: [ListItem(text: "first")])
        let nodes = BlockEncoder.encode([bullet, numbered])
        XCTAssertEqual(nodes.map(\.tag), ["ul", "ol"])
        XCTAssertEqual(listTexts(nodes[0]), ["one", "two"])
        XCTAssertEqual(listTexts(nodes[1]), ["first"])
    }

    func testBulletListRoundTrip() throws {
        let block = Block.bulletList(
            id: UUID(),
            items: [ListItem(text: "one"), ListItem(text: "two")]
        )
        let node = try XCTUnwrap(BlockEncoder.encode(block))
        let decoded = try XCTUnwrap(BlockDecoder.decode(node))

        XCTAssertEqual(node.tag, "ul")
        guard case let .bulletList(_, items) = decoded else {
            return XCTFail("Expected bullet list")
        }
        XCTAssertEqual(items.map(\.text), ["one", "two"])
    }

    func testNumberedListRoundTrip() throws {
        let block = Block.numberedList(
            id: UUID(),
            items: [ListItem(text: "first"), ListItem(text: "second")]
        )
        let node = try XCTUnwrap(BlockEncoder.encode(block))
        let decoded = try XCTUnwrap(BlockDecoder.decode(node))

        XCTAssertEqual(node.tag, "ol")
        guard case let .numberedList(_, items) = decoded else {
            return XCTFail("Expected numbered list")
        }
        XCTAssertEqual(items.map(\.text), ["first", "second"])
    }

    func testFigureEncodesImageAndCaption() throws {
        let url = try XCTUnwrap(URL(string: "https://telegra.ph/file/image.jpg"))
        let node = try XCTUnwrap(
            BlockEncoder.encode(.figure(id: UUID(), imageURL: url, caption: "Caption"))
        )
        XCTAssertEqual(node.tag, "figure")
        let children = try XCTUnwrap(node.children)
        guard case let .node(image) = children[0] else {
            return XCTFail("Expected image child")
        }
        XCTAssertEqual(image.tag, "img")
        XCTAssertEqual(image.attrs?["src"], url.absoluteString)
        guard case let .node(caption) = children[1] else {
            return XCTFail("Expected caption child")
        }
        XCTAssertEqual(caption.tag, "figcaption")
        XCTAssertEqual(text(from: caption), "Caption")
    }

    func testFigureWithoutCaptionOmitsFigcaption() throws {
        let node = try XCTUnwrap(
            BlockEncoder.encode(.figure(id: UUID(), imageURL: exampleURL, caption: ""))
        )
        XCTAssertEqual(node.children?.count, 1)
        XCTAssertFalse(node.children?.contains { child in
            if case let .node(childNode) = child {
                return childNode.tag == "figcaption"
            }
            return false
        } ?? false)
    }

    func testImagelessFigureWithCaptionDegradesToParagraph() throws {
        let node = try XCTUnwrap(
            BlockEncoder.toNodes([
                .figure(id: UUID(), imageURL: nil, caption: "Caption")
            ]).first
        )
        XCTAssertEqual(node.tag, "p")
        XCTAssertEqual(text(from: node), "Caption")
    }

    func testImagelessEmptyFigureIsOmittedFromPublishingNodes() {
        let nodes = BlockEncoder.nodesForPublishing([
            .figure(id: UUID(), imageURL: nil, caption: "")
        ])
        XCTAssertTrue(nodes.isEmpty)
    }

    func testOtherBlockTagsEncode() throws {
        let blocks: [Block] = [
            .quote(id: UUID(), text: "quote"),
            .code(id: UUID(), text: "code"),
            .newDivider(),
            .link(id: UUID(), text: "link", url: exampleURL)
        ]
        let nodes = BlockEncoder.encode(blocks)
        XCTAssertEqual(nodes.map(\.tag), ["blockquote", "pre", "hr", "a"])
        XCTAssertEqual(nodes[3].attrs?["href"], exampleURL.absoluteString)
    }

    func testDecoderReadsAllTelegraphBlockKinds() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/image.jpg"))
        let nodes = [
            TelegraphNode(tag: "p", attrs: nil, children: [.text("p")]),
            TelegraphNode(tag: "h3", attrs: nil, children: [.text("h")]),
            TelegraphNode(tag: "blockquote", attrs: nil, children: [.text("q")]),
            TelegraphNode(tag: "pre", attrs: nil, children: [.text("c")]),
            TelegraphNode(tag: "hr", attrs: nil, children: nil),
            TelegraphNode(
                tag: "figure",
                attrs: nil,
                children: [
                    .node(TelegraphNode(tag: "img", attrs: ["src": url.absoluteString], children: nil)),
                    .node(TelegraphNode(tag: "figcaption", attrs: nil, children: [.text("f")]))
                ]
            ),
            TelegraphNode(tag: "a", attrs: ["href": url.absoluteString], children: [.text("a")])
        ]
        let blocks = BlockDecoder.fromNodes(nodes)
        XCTAssertEqual(blocks.count, nodes.count)
        guard case .paragraph = blocks[0],
              case let .heading(_, level, _) = blocks[1],
              case .quote = blocks[2],
              case .code = blocks[3],
              case .divider = blocks[4],
              case let .figure(_, imageURL, caption) = blocks[5],
              case let .link(_, linkText, linkURL) = blocks[6]
        else {
            return XCTFail("Decoded block kinds did not match")
        }
        XCTAssertEqual(level, 1)
        XCTAssertEqual(imageURL, url)
        XCTAssertEqual(caption, "f")
        XCTAssertEqual(linkText, "a")
        XCTAssertEqual(linkURL, url)
    }

    func testDecoderMapsH4ToHeadingLevelTwo() {
        let node = TelegraphNode(tag: "h4", attrs: nil, children: [.text("subtitle")])
        guard case let .heading(_, level, text) = BlockDecoder.decode(node) else {
            return XCTFail("Expected heading")
        }
        XCTAssertEqual(level, 2)
        XCTAssertEqual(text, "subtitle")
    }

    func testEncodedDataRoundTripsNodeShape() throws {
        let blocks: [Block] = [
            .paragraph(id: UUID(), text: "paragraph"),
            .quote(id: UUID(), text: "quote"),
            .code(id: UUID(), text: "code")
        ]
        let data = try BlockEncoder.encodedData(for: blocks)
        let nodes = try JSONDecoder().decode([TelegraphNode].self, from: data)
        XCTAssertEqual(nodes, BlockEncoder.encode(blocks))
    }

    func testEmptyInputEncodesToEmptyNodes() {
        XCTAssertEqual(BlockEncoder.toNodes([]), [])
        XCTAssertEqual(BlockDecoder.fromNodes([]), [])
    }

    func testPublishingNodesDropEmptyBlocks() {
        let nodes = BlockEncoder.nodesForPublishing([
            .emptyParagraph(),
            .newDivider(),
            .emptyFigure()
        ])
        XCTAssertEqual(nodes.map(\.tag), ["hr"])
    }

    func testContentLimitThrowsForOversizedJSON() {
        let block = Block.paragraph(id: UUID(), text: String(repeating: "x", count: 70_000))
        XCTAssertThrowsError(try BlockEncoder.encodedData(for: [block])) { error in
            guard case let BlockCodingError.contentTooLarge(bytes) = error else {
                return XCTFail("Expected contentTooLarge")
            }
            XCTAssertGreaterThan(bytes, BlockEncoder.maxContentBytes)
        }
        XCTAssertFalse(BlockEncoder.isWithinLimit([block]))
    }

    private func listTexts(_ node: TelegraphNode) -> [String] {
        (node.children ?? []).compactMap { child in
            guard case let .node(item) = child else { return nil }
            return text(from: item)
        }
    }

    private func text(from node: TelegraphNode) -> String {
        (node.children ?? []).map { child in
            switch child {
            case let .text(value):
                value
            case let .node(nested):
                text(from: nested)
            }
        }.joined()
    }

    private var exampleURL: URL {
        URL(string: "https://example.com/image.jpg") ?? URL(fileURLWithPath: "/")
    }
}
