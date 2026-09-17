import Foundation

/// D2 最小块模型。D3 会在此基础上扩展其他块类型。
enum Block: Identifiable, Hashable, Codable {
    case paragraph(id: UUID, text: String)
    case heading(id: UUID, level: Int, text: String)
    case figure(id: UUID, imageURL: URL?, caption: String)

    var id: UUID {
        switch self {
        case .paragraph(let id, _), .heading(let id, _, _), .figure(let id, _, _):
            return id
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case id
        case text
        case level
        case imageURL
        case caption
    }

    private enum Kind: String, Codable {
        case paragraph
        case heading
        case figure
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .type)
        let id = try container.decode(UUID.self, forKey: .id)

        switch kind {
        case .paragraph:
            self = .paragraph(id: id, text: try container.decode(String.self, forKey: .text))
        case .heading:
            self = .heading(id: id,
                            level: try container.decode(Int.self, forKey: .level),
                            text: try container.decode(String.self, forKey: .text))
        case .figure:
            self = .figure(id: id,
                           imageURL: try container.decodeIfPresent(URL.self, forKey: .imageURL),
                           caption: try container.decodeIfPresent(String.self, forKey: .caption) ?? "")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)

        switch self {
        case .paragraph(_, let text):
            try container.encode(Kind.paragraph, forKey: .type)
            try container.encode(text, forKey: .text)
        case .heading(_, let level, let text):
            try container.encode(Kind.heading, forKey: .type)
            try container.encode(level, forKey: .level)
            try container.encode(text, forKey: .text)
        case .figure(_, let imageURL, let caption):
            try container.encode(Kind.figure, forKey: .type)
            try container.encodeIfPresent(imageURL, forKey: .imageURL)
            try container.encode(caption, forKey: .caption)
        }
    }
}

/// 将编辑器块编码为 Telegraph Node。
enum BlockEncoder {
    static func toNodes(_ blocks: [Block]) -> [TelegraphNode] {
        blocks.compactMap(toNode)
    }

    static func toNodes(from blocks: [Block]) -> [TelegraphNode] {
        toNodes(blocks)
    }

    static func toNode(_ block: Block) -> TelegraphNode? {
        switch block {
        case .paragraph(_, let text):
            return TelegraphNode(tag: "p", attrs: nil, children: [.text(text)])
        case .heading(_, let level, let text):
            let tag = level == 1 ? "h3" : "h4"
            return TelegraphNode(tag: tag, attrs: nil, children: [.text(text)])
        case .figure(_, let imageURL, let caption):
            guard let imageURL else {
                return caption.isEmpty
                    ? nil
                    : TelegraphNode(tag: "p", attrs: nil, children: [.text(caption)])
            }

            var children: [TelegraphNode.NodeChild] = [
                .node(TelegraphNode(
                    tag: "img",
                    attrs: ["src": imageURL.absoluteString],
                    children: nil
                ))
            ]
            if !caption.isEmpty {
                children.append(.node(TelegraphNode(
                    tag: "figcaption",
                    attrs: nil,
                    children: [.text(caption)]
                )))
            }
            return TelegraphNode(tag: "figure", attrs: nil, children: children)
        }
    }
}
