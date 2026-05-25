import Cocoa
import SwiftUI
import MemosKit

@MainActor
public class MemosPanelController: NSObject {
    public static let shared = MemosPanelController()

    private override init() {
        super.init()
    }

    public func toggle() {
        QuickMemoPanelController.shared.toggle()
    }

    public func show() {
        QuickMemoPanelController.shared.show()
    }

    public func hide() {
        QuickMemoPanelController.shared.hide()
    }

    public func configure(appState: AppState) {
        QuickMemoPanelController.shared.configure(appState: appState)
    }
}
