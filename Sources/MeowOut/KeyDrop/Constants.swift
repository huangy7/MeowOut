import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    public static let togglePanel = Self("keyDropTogglePanel", default: .init(.semicolon, modifiers: [.command, .shift]))
    public static let toggleMemosQuickCapture = Self("toggleMemosQuickCapture", default: .init(.comma, modifiers: [.command, .shift]))
    public static let toggleMemosBrowserWindow = Self("toggleMemosBrowserWindow", default: .init(.b, modifiers: [.command, .shift]))
    public static let toggleLauncher = Self("toggleLauncher", default: .init(.l, modifiers: [.command, .shift]))
}

extension Notification.Name {
    public static let keyDropPanelDidShow = Notification.Name("keyDropPanelDidShow")
    public static let keyDropDidInject = Notification.Name("keyDropDidInject")
    public static let keyDropRequireAccessibility = Notification.Name("keyDropRequireAccessibility")
}
