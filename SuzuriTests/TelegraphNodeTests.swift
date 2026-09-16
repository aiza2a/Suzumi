import XCTest
@testable import Suzuri

final class TelegraphNodeTests: XCTestCase {

    private func decode(_ json: String) throws -> [TelegraphNode] {
        try JSONDecoder().decode([TelegraphNode].self, from: Data(json.utf8))
    }

    /// 解码 `[{"tag":"p","children":["你好"]}]` → children[0] == .text("你好")
    func testDecodeTextChild() throws {
        let nodes = try decode(#"[{"tag":"p","children":["你好"]}]"#)
        XCTAssertEqual(nodes.count, 1)
        XCTAssertEqual(nodes[0].tag, "p")
        XCTAssertEqual(nodes[0].children?.count, 1)

        guard case .text(let s) = nodes[0].children?[0] else {
            XCTFail("首个子节点应为 .text"); return
        }
        XCTAssertEqual(s, "你好")
    }

    /// 解码混合 `children:["a",{"tag":"b","children":["c"]}]` → [.text, .node] 顺序保持
    func testDecodeMixedChildren() throws {
        let nodes = try decode(#"[{"tag":"p","children":["a",{"tag":"b","children":["c"]}]}]"#)
        let children = try XCTUnwrap(nodes[0].children)
        XCTAssertEqual(children.count, 2)

        guard case .text(let a) = children[0] else {
            XCTFail("第一个应为文本节点"); return
        }
        XCTAssertEqual(a, "a")

        guard case .node(let inner) = children[1] else {
            XCTFail("第二个应为元素节点"); return
        }
        XCTAssertEqual(inner.tag, "b")
        guard case .text(let c) = inner.children?[0] else {
            XCTFail("内层子节点应为文本"); return
        }
        XCTAssertEqual(c, "c")
    }

    /// 编码往返：encode → decode 相等（Equatable）
    func testEncodeRoundTrip() throws {
        let original = TelegraphNode(
            tag: "h3",
            attrs: ["id": "t1"],
            children: [.text("标题"), .node(TelegraphNode(tag: "b", attrs: nil, children: [.text("粗")]))]
        )

        let encoded = try JSONEncoder().encode([original])
        let decoded = try JSONDecoder().decode([TelegraphNode].self, from: encoded)

        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0], original)
    }

    /// attrs 缺省时解码后 attrs == nil，不解码为 {}
    func testAttrsNilWhenAbsent() throws {
        let nodes = try decode(#"[{"tag":"p","children":["x"]}]"#)
        XCTAssertNil(nodes[0].attrs)
    }

    /// attrs 存在时能正确读出键值
    func testAttrsDecoded() throws {
        let nodes = try decode(#"[{"tag":"a","attrs":{"href":"https://e.ex"},"children":["link"]}]"#)
        XCTAssertEqual(nodes[0].attrs?["href"], "https://e.ex")
    }

    /// 文本节点的 nil children：纯 text child 应能被解码为 .text
    func testEmptyChildrenDecodes() throws {
        let nodes = try decode(#"[{"tag":"hr"}]"#)
        XCTAssertNil(nodes[0].children)
    }
}