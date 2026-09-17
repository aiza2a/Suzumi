import Foundation

/// Telegraph API Node。
///
/// Telegraph 的 `Node` 是二态的：既可以是纯文本（DOM 文本节点），
/// 也可以是元素节点 (`NodeElement`)。这里用一个 `NodeChild` 枚举表达，
/// 编解码采用 `singleValueContainer` 先试 object 再回退 string 的写法
/// （参考 dp5a/Telegraph）。
struct TelegraphNode: Codable, Equatable, Sendable {
    /// DOM 元素标签，如 "p" / "h3" / "figure"。文本节点没有该字段。
    var tag: String?
    /// 元素属性，如 ["src": "https://..."]。
    var attrs: [String: String]?
    /// 子节点列表，元素类型为 string(文本节点) 或 object(元素节点)。
    var children: [NodeChild]?

    /// 二态子节点：文本节点或嵌套元素节点。
    enum NodeChild: Codable, Equatable, Sendable {
        case text(String)
        case node(TelegraphNode)

        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            // 先尝试按字符串解码（文本节点），失败再按对象解码（元素节点）。
            if let s = try? c.decode(String.self) {
                self = .text(s)
            } else {
                self = .node(try c.decode(TelegraphNode.self))
            }
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.singleValueContainer()
            switch self {
            case .text(let s): try c.encode(s)
            case .node(let n): try c.encode(n)
            }
        }
    }
}