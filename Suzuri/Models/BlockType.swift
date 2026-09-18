import Foundation

/// The block registry shared by slash commands and Turn into actions.
enum BlockType: String, CaseIterable, Identifiable, Hashable {
    case text
    case heading
    case quote
    case bulletList
    case numberedList
    case code
    case divider
    case figure
    case link

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .text:
            "文本"
        case .heading:
            "标题"
        case .quote:
            "引用"
        case .bulletList:
            "无序列表"
        case .numberedList:
            "有序列表"
        case .code:
            "代码"
        case .divider:
            "分割线"
        case .figure:
            "图片"
        case .link:
            "链接"
        }
    }

    /// SF Symbol name used by the eventual editor menus.
    var icon: String {
        switch self {
        case .text:
            "text.alignleft"
        case .heading:
            "textformat.size"
        case .quote:
            "text.quote"
        case .bulletList:
            "list.bullet"
        case .numberedList:
            "list.number"
        case .code:
            "chevron.left.forwardslash.chevron.right"
        case .divider:
            "minus"
        case .figure:
            "photo"
        case .link:
            "link"
        }
    }

    /// Alias matching the naming used by menu implementations.
    var iconName: String {
        icon
    }

    enum Category: String, CaseIterable, Hashable {
        case text = "Text"
        case lists = "Lists"
        case media = "Media"
        case advanced = "Advanced"

        var displayName: String {
            switch self {
            case .text:
                "文本"
            case .lists:
                "列表"
            case .media:
                "媒体"
            case .advanced:
                "高级"
            }
        }
    }

    var category: Category {
        switch self {
        case .text, .heading:
            .text
        case .bulletList, .numberedList:
            .lists
        case .figure, .link:
            .media
        case .quote, .code, .divider:
            .advanced
        }
    }

    /// A fresh empty block for insertion from a menu.
    var makeEmpty: Block {
        makeBlock(id: UUID(), text: "")
    }

    /// Builds a block while retaining text for Turn into conversions.
    func makeBlock(id: BlockID, text: String) -> Block {
        switch self {
        case .text:
            .paragraph(id: id, text: text)
        case .heading:
            .heading(id: id, level: 1, text: text)
        case .quote:
            .quote(id: id, text: text)
        case .bulletList:
            .bulletList(id: id, items: [ListItem(text: text)])
        case .numberedList:
            .numberedList(id: id, items: [ListItem(text: text)])
        case .code:
            .code(id: id, text: text)
        case .divider:
            .divider(id: id)
        case .figure:
            .figure(id: id, imageURL: nil, caption: text)
        case .link:
            .link(id: id, text: text, url: Self.defaultLinkURL)
        }
    }

    func makeEmptyBlock() -> Block {
        makeEmpty
    }

    /// Menu grouping in registry order.
    static var groupedByCategory: [(category: Category, types: [BlockType])] {
        Category.allCases.compactMap { category in
            let types = allCases.filter { $0.category == category }
            return types.isEmpty ? nil : (category, types)
        }
    }

    /// Types that preserve text when a block is turned into another block.
    static var turnIntoTypes: [BlockType] {
        [.text, .heading, .quote, .bulletList, .numberedList, .code, .link]
    }

    // Compatibility aliases for the terminology used by earlier design drafts.
    static var paragraph: BlockType { .text }
    static var codeBlock: BlockType { .code }

    private static var defaultLinkURL: URL {
        URL(string: "https://example.com") ?? URL(fileURLWithPath: "/")
    }
}
