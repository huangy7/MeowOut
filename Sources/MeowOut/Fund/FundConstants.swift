import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    public static let toggleFundPanel = Self(
        "fundTogglePanel",
        default: .init(.f, modifiers: [.command, .shift])
    )
}
