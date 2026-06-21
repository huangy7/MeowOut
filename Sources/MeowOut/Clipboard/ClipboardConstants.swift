import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    public static let toggleClipboardHistoryPanel = Self(
        "clipboardHistoryTogglePanel",
        default: .init(.c, modifiers: [.command, .shift])
    )
}

extension Notification.Name {
    public static let clipboardHistoryRequireAccessibility = Notification.Name("clipboardHistoryRequireAccessibility")
    public static let clipboardHistoryDidPaste = Notification.Name("clipboardHistoryDidPaste")
}
