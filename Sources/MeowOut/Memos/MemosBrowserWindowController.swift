import AppKit
import SwiftUI

public class MemosBrowserWindowController: NSWindowController {
    public static let shared = MemosBrowserWindowController()

    private var appState: AppState?

    public init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Memos"
        window.center()
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .visible
        
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func configure(appState: AppState) {
        self.appState = appState
        let contentView = MemosRootView()
            .environment(appState)
        window?.contentView = NSHostingView(rootView: contentView)
    }

    public func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func toggle() {
        if window?.isVisible == true {
            window?.orderOut(nil)
        } else {
            show()
        }
    }
}
