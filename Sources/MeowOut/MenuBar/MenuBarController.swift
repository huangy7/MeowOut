import SwiftUI
import AppKit

/// 菜单栏状态栏控制器：手动管理 NSStatusItem + NSPopover（左键面板）+ NSMenu（右键菜单）。
/// 参照 vorssaint-utils 的 StatusItemController 模式：
/// - button 对左/右键都发 action，在 action 里读 NSApp.currentEvent 分流
/// - statusItem.menu 平时保持 nil（否则左键会被 menu 拦截），右键时临时挂载
@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate, NSMenuDelegate {
    static let shared = MenuBarController()

    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let renderer = TrayIconRenderer()
    private var appState: AppState!
    private var frameTimer: Timer?
    /// transient popover 被"点击状态栏图标"关闭后 action 仍会触发，需时间戳防抖避免关不掉
    private var popoverClosedAt = Date.distantPast
    /// 右键菜单显示期间暂停图标帧更新：修改 button.image 会打断 NSMenu 的模态追踪导致菜单闪退
    private var isContextMenuOpen = false

    private override init() {
        super.init()
    }

    func configure(appState: AppState) {
        self.appState = appState

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "MeowOutStatusItem"
        statusItem.behavior = []
        statusItem.isVisible = true
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        setUpPopover()

        renderer.refreshIfNeeded(appState: appState, colorScheme: currentColorScheme())
        updateIcon()

        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        frameTimer = timer
    }

    // MARK: - 点击分流

    @objc private func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    // MARK: - 图标帧轮播

    private func tick() {
        if TrayIconRenderer.shouldAnimate(appState: appState) {
            appState.currentFrameIndex = (appState.currentFrameIndex + 1) % 5
        }
        // 状态/宠物/外观变化检测（0.2s 一次的 Equatable 比较，无需 KVO）
        renderer.refreshIfNeeded(appState: appState, colorScheme: currentColorScheme())
        // 菜单显示期间不要碰 button.image，否则菜单会被打断关闭
        if !isContextMenuOpen {
            updateIcon()
        }
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        if let image = renderer.currentImage(appState: appState), button.image !== image {
            button.image = image
        }
    }

    private func currentColorScheme() -> ColorScheme {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
    }

    // MARK: - 左键 Popover

    private func setUpPopover() {
        popover.behavior = .transient
        popover.delegate = self
        let root = MenuPanelView(appState: appState)
            .environment(appState)
        let host = NSHostingController(rootView: root)
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        popover.contentSize = NSSize(width: 280, height: 400) // 实际高度由 host 的 preferredContentSize 覆盖
    }

    func togglePopover() {
        if popover.isShown {
            closePopover()
            return
        }
        // transient 关闭与本次点击的 action 几乎同时发生，350ms 内拒绝重开
        guard Date().timeIntervalSince(popoverClosedAt) > 0.35 else { return }
        guard let button = statusItem.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        applyAppearanceToPopover()
    }

    func closePopover() {
        guard popover.isShown else { return }
        popover.performClose(nil)
    }

    /// popover 窗口不一定继承 NSApp.appearance，显式同步当前外观模式
    func applyAppearanceToPopover() {
        guard popover.isShown, let window = popover.contentViewController?.view.window else { return }
        window.appearance = MenuVisualEffectView.nsAppearance(for: appState.appearanceMode)
    }

    nonisolated func popoverDidClose(_ notification: Notification) {
        Task { @MainActor in
            self.popoverClosedAt = Date()
        }
    }

    // MARK: - 右键菜单

    private func showContextMenu() {
        if popover.isShown {
            closePopover()
        }
        let lang = appState.language
        let menu = NSMenu()

        let settingsItem = NSMenuItem(
            title: I18n.localized("menu_settings_plain", language: lang),
            action: #selector(openSettings),
            keyEquivalent: ""
        )
        settingsItem.target = self
        settingsItem.image = NSImage(size: .zero) // 抑制 AppKit 自动添加的齿轮图标
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: I18n.localized("menu_quit", language: lang),
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        menu.delegate = self
        isContextMenuOpen = true
        statusItem.button?.performClick(nil)
        // 立刻移除：menu 平时必须为 nil，否则左键会被 menu 拦截而不再走 action
        DispatchQueue.main.async { [weak self] in
            self?.statusItem.menu = nil
        }
    }

    nonisolated func menuDidClose(_ menu: NSMenu) {
        Task { @MainActor in
            self.isContextMenuOpen = false
            self.updateIcon()
        }
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: NSNotification.Name("OpenSettingsWindow"), object: nil)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
