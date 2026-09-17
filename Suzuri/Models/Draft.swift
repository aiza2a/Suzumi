import Foundation
import SwiftData

/// 本地草稿。块内容以 JSON 保存，避免为值类型 Block 建立关系模型。
@Model
final class Draft: Identifiable {
    var id: UUID = UUID()
    var title: String = ""
    var blocksData: Data = Data()
    var updatedAt: Date = .now
    var isPublished: Bool = false
    var pagePath: String?
    var schemaVersion: Int = 1

    init() {}

    init(
        id: UUID = UUID(),
        title: String = "",
        blocksData: Data = Data(),
        updatedAt: Date = .now,
        isPublished: Bool = false,
        pagePath: String? = nil,
        schemaVersion: Int = 1
    ) {
        self.id = id
        self.title = title
        self.blocksData = blocksData
        self.updatedAt = updatedAt
        self.isPublished = isPublished
        self.pagePath = pagePath
        self.schemaVersion = schemaVersion
    }
}
