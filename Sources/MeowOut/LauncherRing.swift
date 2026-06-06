import Foundation

public struct LauncherRing: Codable, Identifiable, Equatable {
    public static let maxTools = 8

    public var id: UUID
    public var name: String
    public var tools: [QuickTool]

    public init(id: UUID = UUID(), name: String, tools: [QuickTool] = []) {
        self.id = id
        self.name = name
        self.tools = Array(tools.prefix(Self.maxTools))
    }
}
