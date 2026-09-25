import SwiftUI
import AppKit

/// 应用级窗口/通知路由：接管原 WindowOpener（依附 MenuBarExtra label 生命周期的透明视图）的全部通知监听。
/// 常驻单例，在 AppDelegate.applicationDidFinishLaunching 中 configure。
@MainActor
final class AppWindowManager {
    static let shared = AppWindowManager()

    private var appState: AppState!
    private var observers: [NSObjectProtocol] = []
    private var windows: [AppWindowID: NSWindow] = [:]

    private enum AppWindowID {
        case settings, breathing, meow2fa
    }

    private init() {}

    func configure(appState: AppState) {
        self.appState = appState
        let nc = NotificationCenter.default

        // MARK: 独立窗口（原 SwiftUI Window scene，改为手动管理）

        observe(nc, NSNotification.Name("OpenSettingsWindow")) { [weak self] _ in
            self?.show(.settings)
        }
        observe(nc, NSNotification.Name("OpenBreathingWindow")) { [weak self] _ in
            self?.show(.breathing)
        }
        observe(nc, NSNotification.Name("OpenMeow2FAWindow")) { [weak self] _ in
            self?.show(.meow2fa)
        }

        // MARK: 面板类开关（直接转调各 PanelController）

        observe(nc, NSNotification.Name("ToggleMemosPanel")) { _ in
            MemosPanelController.shared.toggle()
        }
        observe(nc, .toggleQuickMemoPanel) { _ in
            QuickMemoPanelController.shared.toggle()
        }
        observe(nc, .toggleMemosBrowserWindow) { _ in
            MemosBrowserWindowController.shared.toggle()
        }
        observe(nc, .showMemosBrowserWindow) { _ in
            MemosBrowserWindowController.shared.show()
        }

        // MARK: 辅助功能权限告警

        observe(nc, .clipboardHistoryRequireAccessibility) { [weak self] _ in
            self?.showClipboardAccessibilityAlert()
        }
        observe(nc, .launcherAccessibilityPermissionLost) { [weak self] _ in
            self?.showLauncherAccessibilityAlert()
        }
    }

    private func observe(_ nc: NotificationCenter, _ name: Notification.Name,
                         using block: @escaping (Notification) -> Void) {
        observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { notification in
            MainActor.assumeIsolated { block(notification) }
        })
    }

    // MARK: - 独立窗口管理（原 SwiftUI Window scene 的手动等价物）

    private func show(_ id: AppWindowID) {
        if windows[id] == nil {
            windows[id] = makeWindow(id)
        }
        guard let window = windows[id] else { return }
        window.title = title(for: id)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func title(for id: AppWindowID) -> String {
        let key: String
        switch id {
        case .settings: key = "settings_window_title"
        case .breathing: key = "menu_breathing"
        case .meow2fa: key = "menu_toolbox_2fa"
        }
        return I18n.localized(key, language: appState.language)
    }

    private func makeWindow(_ id: AppWindowID) -> NSWindow {
        let window: NSWindow
        var hasRestoredFrame = false
        switch id {
        case .settings:
            window = hostingWindow(SettingsView(state: appState),
                                   styleMask: [.titled, .closable, .resizable, .miniaturizable])
            window.toolbarStyle = .unified
            window.setFrameAutosaveName("MeowOutSettingsWindow")
            // setFrameAutosaveName 的返回值只表示名字可用，与是否恢复过尺寸无关；
            // 用 setFrameUsingName 判断有无历史尺寸，没有历史尺寸才居中，避免首启落在屏幕角落
            hasRestoredFrame = window.setFrameUsingName("MeowOutSettingsWindow")
        case .breathing:
            window = hostingWindow(BreathingView(),
                                   styleMask: [.titled, .closable, .fullSizeContentView])
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
        case .meow2fa:
            window = hostingWindow(Meow2FAMainView().background(Color.clear),
                                   styleMask: [.titled, .closable, .fullSizeContentView])
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.setContentSize(NSSize(width: 380, height: 600))
        }
        window.isReleasedWhenClosed = false
        if !hasRestoredFrame {
            window.center()
        }
        return window
    }

    private func hostingWindow<Content: View>(_ content: Content, styleMask: NSWindow.StyleMask) -> NSWindow {
        let host = NSHostingController(rootView: content.environment(appState))
        let window = NSWindow(contentViewController: host)
        window.styleMask = styleMask
        return window
    }

    private func showClipboardAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = I18n.localized("clipboard_accessibility_alert_title")
        alert.informativeText = I18n.localized("clipboard_accessibility_alert_message")
        alert.addButton(withTitle: I18n.localized("clipboard_accessibility_open_settings"))
        alert.addButton(withTitle: I18n.localized("accessibility_lost_cancel_btn"))
        if alert.runModal() == .alertFirstButtonReturn {
            ClipboardAccessibilityPermission.openSettingsAfterPrompt()
        }
    }

    private func showLauncherAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = I18n.localized("accessibility_lost_title")
        alert.informativeText = I18n.localized("accessibility_lost_desc")
        alert.addButton(withTitle: I18n.localized("accessibility_lost_open_btn"))
        alert.addButton(withTitle: I18n.localized("accessibility_lost_cancel_btn"))
        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
