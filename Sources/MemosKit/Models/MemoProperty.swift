import Foundation

public struct MemoProperty: Codable, Equatable, Sendable {
    public let hasLink: Bool
    public let hasTaskList: Bool
    public let hasCode: Bool
    public let hasIncompleteTasks: Bool
}
