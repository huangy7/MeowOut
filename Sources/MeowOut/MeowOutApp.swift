import SwiftUI
import AppKit
import MemosKit

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    var monitor: ActivityMonitor?
    private var isStarted = false
    private var lastLanguage: AppState.AppLanguage?
    private var lastAppearanceMode: AppState.AppearanceMode?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 恢复上次异常退出时遗留的系统电源设置
        ClamshellManager.shared.restoreOnQuit()

        // 对于托盘应用，确保激活策略正确
        NSApp.setActivationPolicy(.accessory)

        // 确保上次异常退出时残留的屏幕遮盖/事件拦截被清除
        ScreenOverlayService.shared.stop()

        // 启动自动更新检查器
        UpdateChecker.shared.start()

        // 原 MenuBarExtra label onAppear 的初始化链
        applyAppearanceMode(appState.appearanceMode)
        tryStartEngine()
        appState.initializeKeyboardShortcuts()
        AppWindowManager.shared.configure(appState: appState)
        MemosPanelController.shared.configure(appState: appState)
        QuickMemoPanelController.shared.configure(appState: appState)
        MemosBrowserWindowController.shared.configure(appState: appState)
        ClipboardPanelController.shared.configure(appState: appState)
        FundPanelController.shared.configure(appState: appState)
        QueueProcessor.shared.start()
        ClipboardMonitorService.shared.start()
        ShelfService.shared.start(appState: appState)
        FundService.shared.start()

        MenuBarController.shared.configure(appState: appState)
        startObservingAppState()
    }

    func tryStartEngine() {
        guard !isStarted else { return }
        self.monitor = ActivityMonitor(appState: appState)
        self.monitor?.start()
        CatOverlayController.shared.start(appState: appState)
        isStarted = true
    }

    /// 应用全局外观模式(跟随系统 / 浅色 / 深色)
    func applyAppearanceMode(_ mode: AppState.AppearanceMode) {
        switch mode {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        MenuBarController.shared.applyAppearanceToPopover()
    }

    /// 无窗口时通过 `open -a` 等方式找回：弹出托盘面板作为入口
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            MenuBarController.shared.togglePopover()
        }
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        ClamshellManager.shared.restoreOnQuit()
        PowerAssertionService.shared.disable()
        KeyboardCleaningService.shared.stop()
        ScreenOverlayService.shared.stop()
        ClipboardMonitorService.shared.stop()
        LauncherTriggerService.shared.stop()
    }

    // MARK: - AppState 观察（原 MenuBarExtra label 的 onChange）

    private func startObservingAppState() {
        lastLanguage = appState.language
        lastAppearanceMode = appState.appearanceMode
        withObservationTracking {
            _ = appState.language
            _ = appState.appearanceMode
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.handleObservedStateChange()
            }
        }
    }

    private func handleObservedStateChange() {
        defer { startObservingAppState() }
        if appState.language != lastLanguage {
            // Force engine restart if language changes to pick up new strings
            tryStartEngine()
            ClipboardPanelController.shared.configure(appState: appState)
            FundPanelController.shared.configure(appState: appState)
        }
        if appState.appearanceMode != lastAppearanceMode {
            applyAppearanceMode(appState.appearanceMode)
        }
    }
}

@main
struct MeowOutApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // accessory 应用无主菜单，占位 scene 实际不可达；一切由 AppDelegate 驱动
        Settings { EmptyView() }
    }
}
