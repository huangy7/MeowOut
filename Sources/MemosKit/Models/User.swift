import Foundation

public struct User: Codable, Sendable {
    public let name: String
    public let username: String
    public let displayName: String
    public let avatarUrl: String?
}
