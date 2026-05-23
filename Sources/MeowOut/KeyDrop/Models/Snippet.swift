import Foundation

public struct Snippet: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var content: String
    public var category: String
    
    public init(id: UUID = UUID(), title: String, content: String, category: String = "未分类") {
        self.id = id
        self.title = title
        self.content = content
        self.category = category
    }
    
    enum CodingKeys: String, CodingKey {
        case id, title, content, category
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.title = try container.decode(String.self, forKey: .title)
        self.content = try container.decode(String.self, forKey: .content)
        self.category = try container.decodeIfPresent(String.self, forKey: .category) ?? "未分类"
    }
}
