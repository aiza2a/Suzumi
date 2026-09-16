import Foundation

typealias BlockCodingError = TelegraphError
typealias BlockEncodingError = TelegraphError

struct BlockEncoder {
    static let maxContentBytes = 65_536
    static let contentLimit = maxContentBytes

    static func encode(_ blocks: [Block]) -> [TelegraphNode] {
        blocks.map(toNode)
    }

    static func encode(blocks: [Block]) -> [TelegraphNode] {
        encode(blocks)
    }

    static func toNodes(_ blocks: [Block]) -> [TelegraphNode] {
        encode(blocks)
    }

    static func toNodes(_ block: Block) -> [TelegraphNode] {
        [toNode(block)]
    }

    static func toNodes(blocks: [Block]) -> [TelegraphNode] {
        encode(blocks)
    }

    static func toNodes(from blocks: [Block]) -> [TelegraphNode] {
        encode(blocks)
    }

    static func encode(_ block: Block) -> TelegraphNode? {
        toNode(block)
    }

    static func toNode(_ block: Block) -> TelegraphNode {
        switch block {
        case let .paragraph(_, text):
            node(tag: "p", children: [.text(text)])
        case let .heading(_, level, text):
            node(tag: level <= 1 ? "h3" : "h4", children: [.text(text)])
        case let .bulletList(_, items):
            listNode(tag: "ul", items: items)
        case let .numberedList(_, items):
            listNode(tag: "ol", items: items)
        case let .quote(_, text):
            node(tag: "blockquote", children: [.text(text)])
        case let .code(_, text):
            node(tag: "pre", children: [.text(text)])
        case .divider:
            TelegraphNode(tag: "hr", attrs: nil, children: nil)
        case let .figure(_, imageURL, caption):
            figureNode(imageURL: imageURL, caption: caption)
        case let .link(_, text, url):
            node(tag: "a", attrs: ["href": url.absoluteString], children: [.text(text)])
        }
    }

    /// Encodes the nodes as Telegraph JSON and enforces the 64 KiB content limit.
    static func encodedData(
        for blocks: [Block],
        maxBytes: Int = maxContentBytes
    ) throws -> Data {
        let data = try JSONEncoder().encode(encode(blocks))
        guard data.count <= maxBytes else {
            throw BlockCodingError.contentTooLarge(bytes: data.count)
        }
        return data
    }

    static func encodeData(_ blocks: [Block], maxBytes: Int = maxContentBytes) throws -> Data {
        try encodedData(for: blocks, maxBytes: maxBytes)
    }

    static func data(for blocks: [Block], maxBytes: Int = maxContentBytes) throws -> Data {
        try encodedData(for: blocks, maxBytes: maxBytes)
    }

    static func validateSize(
        of blocks: [Block],
        maxBytes: Int = maxContentBytes
    ) throws {
        _ = try encodedData(for: blocks, maxBytes: maxBytes)
    }

    static func validateSize(
        of nodes: [TelegraphNode],
        maxBytes: Int = maxContentBytes
    ) throws {
        let data = try JSONEncoder().encode(nodes)
        guard data.count <= maxBytes else {
            throw BlockCodingError.contentTooLarge(bytes: data.count)
        }
    }

    static func isWithinLimit(
        _ blocks: [Block],
        maxBytes: Int = maxContentBytes
    ) -> Bool {
        do {
            try validateSize(of: blocks, maxBytes: maxBytes)
            return true
        } catch {
            return false
        }
    }

    /// Drops empty blocks before publication while preserving structural dividers.
    static func nodesForPublishing(_ blocks: [Block]) -> [TelegraphNode] {
        let publishable = blocks.filter { block in
            if case .divider = block {
                return true
            }
            return !block.isEmpty
        }
        return encode(publishable)
    }

    private static func node(
        tag: String,
        attrs: [String: String]? = nil,
        children: [TelegraphNode.NodeChild]
    ) -> TelegraphNode {
        TelegraphNode(tag: tag, attrs: attrs, children: children)
    }

    private static func listNode(tag: String, items: [ListItem]) -> TelegraphNode {
        let children = items.map { item in
            TelegraphNode.NodeChild.node(node(tag: "li", children: [.text(item.text)]))
        }
        return node(tag: tag, children: children)
    }

    private static func figureNode(imageURL: URL?, caption: String) -> TelegraphNode {
        var children: [TelegraphNode.NodeChild] = []
        if let imageURL {
            let image = node(tag: "img", attrs: ["src": imageURL.absoluteString], children: [])
            children.append(.node(image))
        }
        if !caption.isEmpty {
            let figcaption = node(tag: "figcaption", children: [.text(caption)])
            children.append(.node(figcaption))
        }
        return node(tag: "figure", children: children)
    }
}

/// Telegraph nodes do not carry editor block IDs. Decoding intentionally creates new UUIDs,
/// so reloading a node tree rebuilds editor identity rather than attempting to preserve it.
struct BlockDecoder {
    static func decode(_ nodes: [TelegraphNode]) -> [Block] {
        nodes.compactMap(decode(_:))
    }

    static func decode(nodes: [TelegraphNode]) -> [Block] {
        decode(nodes)
    }

    static func fromNodes(_ nodes: [TelegraphNode]) -> [Block] {
        decode(nodes)
    }

    static func fromNodes(nodes: [TelegraphNode]) -> [Block] {
        decode(nodes)
    }

    static func decode(_ node: TelegraphNode) -> Block? {
        let tag = node.tag?.lowercased()
        switch tag {
        case nil:
            return .paragraph(id: UUID(), text: text(from: node.children))
        case "p":
            return .paragraph(id: UUID(), text: text(from: node.children))
        case "h1", "h3":
            return .heading(id: UUID(), level: 1, text: text(from: node.children))
        case "h2", "h4", "h5", "h6":
            return .heading(id: UUID(), level: 2, text: text(from: node.children))
        case "ul":
            return .bulletList(id: UUID(), items: listItems(from: node.children))
        case "ol":
            return .numberedList(id: UUID(), items: listItems(from: node.children))
        case "blockquote", "aside":
            return .quote(id: UUID(), text: text(from: node.children))
        case "pre", "code":
            return .code(id: UUID(), text: text(from: node.children))
        case "hr":
            return .divider(id: UUID())
        case "figure":
            return figure(from: node)
        case "img":
            return figure(fromImage: node)
        case "a":
            guard let href = node.attrs?["href"], let url = URL(string: href) else {
                return nil
            }
            return .link(id: UUID(), text: text(from: node.children), url: url)
        default:
            return nil
        }
    }

    private static func listItems(from children: [TelegraphNode.NodeChild]?) -> [ListItem] {
        guard let children else { return [] }
        return children.compactMap { child in
            guard case let .node(childNode) = child,
                  childNode.tag?.lowercased() == "li"
            else {
                return nil
            }
            return ListItem(text: text(from: childNode.children))
        }
    }

    private static func figure(from node: TelegraphNode) -> Block {
        var imageURL: URL?
        var caption = ""
        for child in node.children ?? [] {
            guard case let .node(childNode) = child else { continue }
            switch childNode.tag?.lowercased() {
            case "img":
                if let source = childNode.attrs?["src"] {
                    imageURL = URL(string: source)
                }
            case "figcaption":
                caption += text(from: childNode.children)
            default:
                break
            }
        }
        return .figure(id: UUID(), imageURL: imageURL, caption: caption)
    }

    private static func figure(fromImage node: TelegraphNode) -> Block {
        let source = node.attrs?["src"].flatMap { URL(string: $0) }
        return .figure(id: UUID(), imageURL: source, caption: "")
    }

    private static func text(from children: [TelegraphNode.NodeChild]?) -> String {
        guard let children else { return "" }
        return children.map { child in
            switch child {
            case let .text(value):
                value
            case let .node(node):
                text(from: node.children)
            }
        }.joined()
    }
}
