import Foundation

public enum MemoVisibility: String, Codable, CaseIterable, Sendable {
    case `private` = "PRIVATE"
    case protected = "PROTECTED"
    case `public` = "PUBLIC"
}
