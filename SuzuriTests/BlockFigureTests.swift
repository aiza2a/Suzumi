import Foundation
import XCTest
@testable import Suzuri

final class BlockFigureTests: XCTestCase {
    private let imageURL = URL(string: "https://qu.ax/file/example.jpg")!

    private func children(of node: TelegraphNode) -> [TelegraphNode.NodeChild] {
        node.children ?? []
    }

    private func childNode(tag: String, in node: TelegraphNode) throws -> TelegraphNode {
        let match = try XCTUnwrap(children(of: node).compactMap { child -> TelegraphNode? in
            guard case .node(let node) = child, node.tag == tag else { return nil }
            return node
        }.first)
        return match
    }

    func testFigureEncodesImageSource() throws {
        let block = Block.figure(id: UUID(), imageURL: imageURL, caption: "")
        let figure = try XCTUnwrap(BlockEncoder.toNodes([block]).first)
        let image = try childNode(tag: "img", in: figure)

        XCTAssertEqual(figure.tag, "figure")
        XCTAssertEqual(image.attrs?["src"], imageURL.absoluteString)
    }

    func testEmptyCaptionOmitsFigcaption() throws {
        let block = Block.figure(id: UUID(), imageURL: imageURL, caption: "")
        let figure = try XCTUnwrap(BlockEncoder.toNodes([block]).first)

        let hasCaption = children(of: figure).contains { child in
            guard case .node(let node) = child else { return false }
            return node.tag == "figcaption"
        }
        XCTAssertFalse(hasCaption)
    }

    func testNonEmptyCaptionEncodesFigcaptionText() throws {
        let block = Block.figure(id: UUID(), imageURL: imageURL, caption: "说明文字")
        let figure = try XCTUnwrap(BlockEncoder.toNodes([block]).first)
        let caption = try childNode(tag: "figcaption", in: figure)

        guard case .text(let text) = try XCTUnwrap(caption.children?.first) else {
            return XCTFail("figcaption 应包含文本节点")
        }
        XCTAssertEqual(text, "说明文字")
    }

    func testFigureRoundTripsThroughJSONEncoder() throws {
        let original = Block.figure(id: UUID(), imageURL: imageURL, caption: "一张图")

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Block.self, from: encoded)

        XCTAssertEqual(decoded, original)
    }

    func testParagraphAndHeadingUseTelegraphTags() throws {
        let paragraph = Block.paragraph(id: UUID(), text: "正文")
        let heading = Block.heading(id: UUID(), level: 1, text: "标题")
        let subheading = Block.heading(id: UUID(), level: 2, text: "小标题")

        let nodes = BlockEncoder.toNodes([paragraph, heading, subheading])

        XCTAssertEqual(nodes.map(\.tag), ["p", "h3", "h4"])
    }

    func testFigureWithoutImageStillEncodesCaptionOnly() throws {
        let block = Block.figure(id: UUID(), imageURL: nil, caption: "待上传")
        let figure = try XCTUnwrap(BlockEncoder.toNodes([block]).first)

        XCTAssertEqual(children(of: figure).count, 1)
        guard case .node(let caption) = try XCTUnwrap(children(of: figure).first) else {
            return XCTFail("应只有 figcaption 节点")
        }
        XCTAssertEqual(caption.tag, "figcaption")
    }
}
