import Foundation

public enum ClipboardHistoryToggleCommand {
    @discardableResult
    public static func handle(
        isEnabled: Bool,
        togglePanel: () -> Void
    ) -> Bool {
        guard isEnabled else {
            return false
        }

        togglePanel()
        return true
    }
}
