import Foundation

/// 已发布文章的远端表示。
struct Page: Codable, Identifiable, Hashable, Sendable {
    let path: String
    let url: String
    let title: String
    let description: String
    var authorName: String?
    var authorUrl: String?
    var imageUrl: String?
    var content: [TelegraphNode]?
    let views: Int
    let canEdit: Bool
    /// Whether the response explicitly contained `can_edit`.
    /// `getPage` responses from some mirrors omit this field.
    var hasCanEditField: Bool

    var id: String { path }

    init(
        path: String,
        url: String,
        title: String,
        description: String,
        authorName: String? = nil,
        authorUrl: String? = nil,
        imageUrl: String? = nil,
        content: [TelegraphNode]? = nil,
        views: Int = 0,
        canEdit: Bool = false
    ) {
        self.path = path
        self.url = url
        self.title = title
        self.description = description
        self.authorName = authorName
        self.authorUrl = authorUrl
        self.imageUrl = imageUrl
        self.content = content
        self.views = views
        self.canEdit = canEdit
        self.hasCanEditField = true
    }

    private enum CodingKeys: String, CodingKey {
        case path
        case url
        case title
        case description
        case authorName = "author_name"
        case authorUrl = "author_url"
        case imageUrl = "image_url"
        case content
        case views
        case canEdit = "can_edit"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        url = try container.decode(String.self, forKey: .url)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        authorName = try container.decodeIfPresent(String.self, forKey: .authorName)
        authorUrl = try container.decodeIfPresent(String.self, forKey: .authorUrl)
        imageUrl = try container.decodeIfPresent(String.self, forKey: .imageUrl)
        content = try Self.decodeContent(from: container)
        views = try container.decodeIfPresent(Int.self, forKey: .views) ?? 0
        hasCanEditField = container.contains(.canEdit)
        canEdit = try container.decodeIfPresent(Bool.self, forKey: .canEdit) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(path, forKey: .path)
        try container.encode(url, forKey: .url)
        try container.encode(title, forKey: .title)
        try container.encode(description, forKey: .description)
        try container.encodeIfPresent(authorName, forKey: .authorName)
        try container.encodeIfPresent(authorUrl, forKey: .authorUrl)
        try container.encodeIfPresent(imageUrl, forKey: .imageUrl)
        try container.encodeIfPresent(content, forKey: .content)
        try container.encode(views, forKey: .views)
        if hasCanEditField {
            try container.encode(canEdit, forKey: .canEdit)
        }
    }

    private static func decodeContent(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> [TelegraphNode]? {
        guard container.contains(.content) else {
            return nil
        }
        if try container.decodeNil(forKey: .content) {
            return nil
        }
        if let nodes = try? container.decode([TelegraphNode].self, forKey: .content) {
            return nodes
        }
        let strings = try container.decode([String].self, forKey: .content)
        return strings.map {
            TelegraphNode(tag: "p", attrs: nil, children: [.text($0)])
        }
    }

    /// Returns a copy with an explicit edit permission.
    func withCanEdit(_ canEdit: Bool) -> Page {
        var page = Page(
            path: path,
            url: url,
            title: title,
            description: description,
            authorName: authorName,
            authorUrl: authorUrl,
            imageUrl: imageUrl,
            content: content,
            views: views,
            canEdit: canEdit
        )
        page.hasCanEditField = true
        return page
    }

    /// Reuses a list response's edit permission when a detail response omits it.
    func preservingCanEdit(from original: Page?, fallback: Bool = false) -> Page {
        guard !hasCanEditField else { return self }
        var page = Page(
            path: path,
            url: url,
            title: title,
            description: description,
            authorName: authorName,
            authorUrl: authorUrl,
            imageUrl: imageUrl,
            content: content,
            views: views,
            canEdit: original?.canEdit ?? fallback
        )
        page.hasCanEditField = original?.hasCanEditField ?? fallback
        return page
    }

    static func == (lhs: Page, rhs: Page) -> Bool {
        lhs.path == rhs.path
            && lhs.url == rhs.url
            && lhs.title == rhs.title
            && lhs.description == rhs.description
            && lhs.authorName == rhs.authorName
            && lhs.authorUrl == rhs.authorUrl
            && lhs.imageUrl == rhs.imageUrl
            && lhs.content == rhs.content
            && lhs.views == rhs.views
            && lhs.canEdit == rhs.canEdit
    }

    func hash(into hasher: inout Hasher) {
        // `path` is stable and sufficient for navigation identity. Hashing a single
        // field also avoids making TelegraphNode's attribute dictionary order matter.
        hasher.combine(path)
    }
}

/// `getPageList` 的远端结果。
struct PageList: Codable, Equatable, Sendable {
    let totalCount: Int
    let pages: [Page]

    var total: Int { totalCount }

    private enum CodingKeys: String, CodingKey {
        case totalCount = "total_count"
        case pages
    }
}

// Compatibility names for callers that use the API layer terminology.
typealias PageListResponse = PageList
typealias PageListData = PageList
