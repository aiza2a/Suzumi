import Foundation

// MARK: - Block ID

typealias BlockID = UUID

// MARK: - List Items

struct ListItem: Identifiable, Hashable, Codable {
    let id: UUID
    var text: String

    init(id: UUID = UUID(), text: String = "") {
        self.id = id
        self.text = text
    }
}

/// Compatibility name for callers that used the D1/D2 list model draft.
typealias BlockListItem = ListItem

// MARK: - Block

enum Block: Identifiable, Hashable, Codable {
    case paragraph(id: BlockID, text: String)
    case heading(id: BlockID, level: Int, text: String)
    case bulletList(id: BlockID, items: [ListItem])
    case numberedList(id: BlockID, items: [ListItem])
    case quote(id: BlockID, text: String)
    case code(id: BlockID, text: String)
    case divider(id: BlockID)
    case figure(id: BlockID, imageURL: URL?, caption: String)
    case link(id: BlockID, text: String, url: URL)

    private enum CodingKeys: String, CodingKey {
        case type
        case id
        case text
        case level
        case items
        case imageURL
        case caption
        case url
    }

    private enum Kind: String, Codable {
        case paragraph
        case heading
        case bulletList
        case numberedList
        case quote
        case code
        case divider
        case figure
        case link
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .type)
        let id = try container.decode(BlockID.self, forKey: .id)
        switch kind {
        case .paragraph:
            self = .paragraph(id: id, text: try container.decode(String.self, forKey: .text))
        case .heading:
            self = .heading(
                id: id,
                level: try container.decode(Int.self, forKey: .level),
                text: try container.decode(String.self, forKey: .text)
            )
        case .bulletList:
            self = .bulletList(
                id: id,
                items: try container.decodeIfPresent([ListItem].self, forKey: .items) ?? []
            )
        case .numberedList:
            self = .numberedList(
                id: id,
                items: try container.decodeIfPresent([ListItem].self, forKey: .items) ?? []
            )
        case .quote:
            self = .quote(id: id, text: try container.decode(String.self, forKey: .text))
        case .code:
            self = .code(id: id, text: try container.decode(String.self, forKey: .text))
        case .divider:
            self = .divider(id: id)
        case .figure:
            self = .figure(
                id: id,
                imageURL: try container.decodeIfPresent(URL.self, forKey: .imageURL),
                caption: try container.decodeIfPresent(String.self, forKey: .caption) ?? ""
            )
        case .link:
            self = .link(
                id: id,
                text: try container.decode(String.self, forKey: .text),
                url: try container.decode(URL.self, forKey: .url)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        switch self {
        case let .paragraph(_, text):
            try container.encode(Kind.paragraph, forKey: .type)
            try container.encode(text, forKey: .text)
        case let .heading(_, level, text):
            try container.encode(Kind.heading, forKey: .type)
            try container.encode(level, forKey: .level)
            try container.encode(text, forKey: .text)
        case let .bulletList(_, items):
            try container.encode(Kind.bulletList, forKey: .type)
            try container.encode(items, forKey: .items)
        case let .numberedList(_, items):
            try container.encode(Kind.numberedList, forKey: .type)
            try container.encode(items, forKey: .items)
        case let .quote(_, text):
            try container.encode(Kind.quote, forKey: .type)
            try container.encode(text, forKey: .text)
        case let .code(_, text):
            try container.encode(Kind.code, forKey: .type)
            try container.encode(text, forKey: .text)
        case .divider:
            try container.encode(Kind.divider, forKey: .type)
        case let .figure(_, imageURL, caption):
            try container.encode(Kind.figure, forKey: .type)
            try container.encodeIfPresent(imageURL, forKey: .imageURL)
            try container.encode(caption, forKey: .caption)
        case let .link(_, text, url):
            try container.encode(Kind.link, forKey: .type)
            try container.encode(text, forKey: .text)
            try container.encode(url, forKey: .url)
        }
    }

    var id: BlockID {
        switch self {
        case let .paragraph(id, _),
             let .heading(id, _, _),
             let .bulletList(id, _),
             let .numberedList(id, _),
             let .quote(id, _),
             let .code(id, _),
             let .divider(id),
             let .figure(id, _, _),
             let .link(id, _, _):
            id
        }
    }

    /// Text edited directly by a text view. List items are edited separately.
    var textContent: String? {
        get {
            switch self {
            case let .paragraph(_, text),
                 let .heading(_, _, text),
                 let .quote(_, text),
                 let .code(_, text),
                 let .link(_, text, _):
                text
            default:
                nil
            }
        }
        set {
            guard let newValue else { return }
            switch self {
            case let .paragraph(id, _):
                self = .paragraph(id: id, text: newValue)
            case let .heading(id, level, _):
                self = .heading(id: id, level: level, text: newValue)
            case let .quote(id, _):
                self = .quote(id: id, text: newValue)
            case let .code(id, _):
                self = .code(id: id, text: newValue)
            case let .link(id, _, url):
                self = .link(id: id, text: newValue, url: url)
            default:
                break
            }
        }
    }

    /// Whether the block has directly editable text.
    var isTextBlock: Bool {
        textContent != nil
    }

    var isListBlock: Bool {
        switch self {
        case .bulletList, .numberedList:
            true
        default:
            false
        }
    }

    var isEmpty: Bool {
        switch self {
        case let .paragraph(_, text),
             let .heading(_, _, text),
             let .quote(_, text),
             let .code(_, text),
             let .link(_, text, _):
            text.isBlank
        case let .bulletList(_, items), let .numberedList(_, items):
            items.allSatisfy { $0.text.isBlank }
        case let .figure(_, imageURL, caption):
            imageURL == nil && caption.isBlank
        case .divider:
            false
        }
    }

    static func makeEmpty(_ type: BlockType) -> Block {
        type.makeEmpty
    }

    static func emptyParagraph() -> Block {
        .paragraph(id: UUID(), text: "")
    }

    static func emptyHeading(level: Int = 1) -> Block {
        .heading(id: UUID(), level: level, text: "")
    }

    static func emptyBulletList() -> Block {
        .bulletList(id: UUID(), items: [ListItem()])
    }

    static func emptyNumberedList() -> Block {
        .numberedList(id: UUID(), items: [ListItem()])
    }

    static func emptyQuote() -> Block {
        .quote(id: UUID(), text: "")
    }

    static func emptyCode() -> Block {
        .code(id: UUID(), text: "")
    }

    static func emptyCodeBlock() -> Block {
        emptyCode()
    }

    static func emptyQuoteBlock() -> Block {
        emptyQuote()
    }

    static func emptyBlockQuote() -> Block {
        emptyQuote()
    }

    static func emptyDivider() -> Block {
        newDivider()
    }

    static func newDivider() -> Block {
        .divider(id: UUID())
    }

    static func emptyFigure() -> Block {
        .figure(id: UUID(), imageURL: nil, caption: "")
    }

    static func emptyLink() -> Block {
        .link(id: UUID(), text: "", url: Self.defaultLinkURL)
    }

    private static var defaultLinkURL: URL {
        URL(string: "https://example.com") ?? URL(fileURLWithPath: "/")
    }
}

private extension String {
    var isBlank: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
