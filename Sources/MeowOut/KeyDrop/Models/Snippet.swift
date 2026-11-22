import Foundation

public struct Snippet: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var content: String
    public var category: String
    public var createdAt: Date?
    public var updatedAt: Date?

    public init(
        id: UUID = UUID(),
        title: String,
        content: String,
        category: String = KeyDropConstants.categoryUncategorized,
        createdAt: Date? = Date(),
        updatedAt: Date? = Date()
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.category = category
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, title, content, category, createdAt, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.title = try container.decode(String.self, forKey: .title)
        self.content = try container.decode(String.self, forKey: .content)
        self.category = try container.decodeIfPresent(String.self, forKey: .category) ?? KeyDropConstants.categoryUncategorized
        self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
    }
}
