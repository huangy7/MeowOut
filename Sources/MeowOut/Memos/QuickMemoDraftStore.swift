import Foundation

public struct QuickMemoDraft: Codable, Equatable, Sendable {
    public var content: String
    public var visibility: String
    public var updatedAt: Date

    public init(content: String, visibility: String, updatedAt: Date = Date()) {
        self.content = content
        self.visibility = visibility
        self.updatedAt = updatedAt
    }
}

public final class QuickMemoDraftStore: @unchecked Sendable {
    public static let shared = QuickMemoDraftStore()

    private let defaults: UserDefaults
    private let key = "memosQuickMemoDraft"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> QuickMemoDraft? {
        guard let data = defaults.data(forKey: key) else {
            return nil
        }

        return try? JSONDecoder().decode(QuickMemoDraft.self, from: data)
    }

    public func save(_ draft: QuickMemoDraft) {
        guard !draft.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            clear()
            return
        }

        guard let data = try? JSONEncoder().encode(draft) else {
            return
        }

        defaults.set(data, forKey: key)
    }

    public func clear() {
        defaults.removeObject(forKey: key)
    }
}
