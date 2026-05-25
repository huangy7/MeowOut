import AppKit
import SwiftUI

@MainActor
public final class QuickMemoWindowController: NSWindowController {
    public static let shared = QuickMemoWindowController()

    private var appState: AppState?
    private var titleObserver: NSObjectProtocol?

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 460),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = I18n.localized("memos_quick_title_default")
        window.center()
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .visible
        window.toolbarStyle = .unified
        
        let toolbar = NSToolbar(identifier: "QuickMemoToolbar")
        toolbar.showsBaselineSeparator = false
        window.toolbar = toolbar

        super.init(window: window)

        titleObserver = NotificationCenter.default.addObserver(
            forName: .quickMemoTitleDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let title = notification.userInfo?["title"] as? String else {
                return
            }

            self?.window?.title = title
        }
    }

    deinit {
        if let titleObserver {
            NotificationCenter.default.removeObserver(titleObserver)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func configure(appState: AppState) {
        self.appState = appState
        window?.contentView = NSHostingView(rootView: QuickMemoView().environment(appState))
    }

    public func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func hide() {
        window?.orderOut(nil)
    }

    public func toggle() {
        if window?.isVisible == true {
            hide()
        } else {
            show()
        }
    }
}
