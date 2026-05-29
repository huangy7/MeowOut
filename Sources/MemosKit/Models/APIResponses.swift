import Foundation

public struct ListMemosResponse: Codable, Sendable {
    public let memos: [Memo]
    public let nextPageToken: String?
}

public struct UserStats: Codable, Sendable {
    public let name: String
    public let tagCount: [String: Int]
    public let memoCreatedTimestamps: [Date]
    public let pinnedMemos: [String]
    public let totalMemoCount: Int
}

struct GetCurrentUserResponse: Codable {
    let user: User
}

struct CreateMemoBody: Codable {
    let content: String
    let visibility: MemoVisibility
    let attachments: [Attachment]?
}

struct UpdateMemoBody: Codable {
    let name: String
    var content: String?
    var visibility: MemoVisibility?
    var state: MemoState?
    var pinned: Bool?
    var attachments: [Attachment]?
}
