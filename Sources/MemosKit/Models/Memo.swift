import Foundation

public struct Memo: Codable, Identifiable, Equatable, Sendable {
    public let name: String
    public let creator: String
    public let createTime: Date
    public let updateTime: Date
    public var content: String
    public var visibility: MemoVisibility
    public var state: MemoState
    public let tags: [String]
    public var pinned: Bool
    public let snippet: String?
    public let property: MemoProperty?

    public var id: String {
        String(name.split(separator: "/").last ?? "")
    }

    public init(
        name: String, creator: String, createTime: Date, updateTime: Date,
        content: String, visibility: MemoVisibility, state: MemoState,
        tags: [String], pinned: Bool, snippet: String?, property: MemoProperty?
    ) {
        self.name = name
        self.creator = creator
        self.createTime = createTime
        self.updateTime = updateTime
        self.content = content
        self.visibility = visibility
        self.state = state
        self.tags = tags
        self.pinned = pinned
        self.snippet = snippet
        self.property = property
    }
}
