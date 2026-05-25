import AppKit

@MainActor
public final class QuickMemoPanelController {
    public static let shared = QuickMemoPanelController()

    private init() {
    }

    public func configure(appState: AppState) {
        QuickMemoWindowController.shared.configure(appState: appState)
    }

    public func toggle() {
        QuickMemoWindowController.shared.toggle()
    }

    public func show() {
        QuickMemoWindowController.shared.show()
    }

    public func hide() {
        QuickMemoWindowController.shared.hide()
    }
}
