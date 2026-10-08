import AppKit
import SwiftUI

public class MemosBrowserWindowController: NSWindowController {
    public static let shared = MemosBrowserWindowController()

    private var appState: AppState?

    public init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1240, height: 780),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Memos"
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .visible
        window.minSize = NSSize(width: 1160, height: 600)

        super.init(window: window)

        // 自动保存名必须在 super.init(window:) 之后再设置：
        // NSWindowController 装载窗口时会把自身的 windowFrameAutosaveName（默认为空串）写回 window，
        // 而空串在 AppKit 中表示"不保存任何信息"。提前设置会被这次写回清空，
        // 导致窗口尺寸与位置无法跨启动记忆。
        window.setFrameAutosaveName("MeowOutMemosBrowserWindow")
        if !window.setFrameUsingName("MeowOutMemosBrowserWindow") {
            window.center()
        }
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
