import SwiftUI
import AppKit
import MemosKit

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var appState: AppState?
    var monitor: ActivityMonitor?
    private var isStarted = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 对于托盘应用，确保激活策略正确
        NSApp.setActivationPolicy(.accessory)
        
        // 确保上次异常退出时残留的屏幕遮盖/事件拦截被清除
        ScreenOverlayService.shared.stop()
        
        // 启动自动更新检查器
        UpdateChecker.shared.start()
    }

    func tryStartEngine() {
        guard let state = appState, !isStarted else { return }
        self.monitor = ActivityMonitor(appState: state)
        self.monitor?.start()
        CatOverlayController.shared.start(appState: state)
        isStarted = true
    }

    func applicationWillTerminate(_ notification: Notification) {
        PowerAssertionService.shared.disable()
        KeyboardCleaningService.shared.stop()
        ScreenOverlayService.shared.stop()
        ClipboardMonitorService.shared.stop()
        LauncherTriggerService.shared.stop()
    }
}


struct WindowOpener: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenSettingsWindow"))) { _ in
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "settings")
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenStatisticsWindow"))) { _ in
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "statistics")
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenBreathingWindow"))) { _ in
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "breathing")
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenMeow2FAWindow"))) { _ in
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "meow2fa")
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenSnippetManagerWindow"))) { _ in
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "snippet-manager")
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ToggleMemosPanel"))) { _ in
                MemosPanelController.shared.toggle()
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleQuickMemoPanel)) { _ in
                QuickMemoPanelController.shared.toggle()
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleMemosBrowserWindow)) { _ in
                MemosBrowserWindowController.shared.toggle()
            }
            .onReceive(NotificationCenter.default.publisher(for: .showMemosBrowserWindow)) { _ in
                MemosBrowserWindowController.shared.show()
            }
            .onReceive(NotificationCenter.default.publisher(for: .clipboardHistoryRequireAccessibility)) { _ in
                showAccessibilityPermissionAlert()
            }
            .onReceive(NotificationCenter.default.publisher(for: .launcherAccessibilityPermissionLost)) { _ in
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

    private func showAccessibilityPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = I18n.localized("clipboard_accessibility_alert_title")
        alert.informativeText = I18n.localized("clipboard_accessibility_alert_message")
        alert.addButton(withTitle: I18n.localized("clipboard_accessibility_open_settings"))
        alert.addButton(withTitle: I18n.localized("accessibility_lost_cancel_btn"))
        if alert.runModal() == .alertFirstButtonReturn {
            ClipboardAccessibilityPermission.openSettingsAfterPrompt()
        }
    }
}

/// 独立的图标视图，最小化重绘范围
struct TrayIconView: View {
    @Bindable var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    let animationTimer = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()
    

    
    private var trayIconConfig: (String, NSColor) {
        switch appState.currentState {
        case .working: return ("cat.fill", .black) // Not used for tinting when isTemplate=true
        case .breathing: return ("cat.fill", NSColor.systemTeal)
        case .alerting: return ("cat.fill", NSColor.orange)
        case .resting: return ("cat.fill", NSColor.red)
        case .overworking: return ("cat.fill", NSColor.red)
        case .paused: return ("pause.circle", NSColor.lightGray)
        case .idle: return ("cat.fill", NSColor.lightGray)
        }
    }
    
    // 🖼️ 核心优化：图像缓存
    @State private var frameCache: [Int: NSImage] = [:]
    @State private var staticCache: NSImage?
    @State private var lastCachedState: AppPhase?
    @State private var lastCachedColor: NSColor?
    @State private var lastCachedPet: AppState.PetType?
    @State private var lastCachedColorScheme: ColorScheme?
    @State private var lastCachedUseClassic: Bool?

    var body: some View {
        Group {
            if let image = currentImage {
                Image(nsImage: image)
            } else {
                Image(systemName: trayIconConfig.0)
            }
        }
        .frame(width: 32, height: 18)
        .onReceive(animationTimer) { _ in
            if appState.isWalking {
                appState.currentFrameIndex = (appState.currentFrameIndex + 1) % 5
            }
        }
        .onAppear {
            prepareCache()
        }
        .onChange(of: appState.currentState) { _, _ in prepareCache() }
        .onChange(of: appState.selectedPet) { _, _ in prepareCache() }
        .onChange(of: colorScheme) { _, _ in prepareCache() }
        .onChange(of: appState.useClassicTrayIcon) { _, _ in prepareCache() }
    }
    
    private var currentImage: NSImage? {
        if appState.isWalking {
            return frameCache[appState.currentFrameIndex]
        } else {
            return staticCache
        }
    }
    
    private var robotLedColor: Color {
        switch appState.currentState {
        case .working, .idle: return Color(red: 91/255, green: 212/255, blue: 230/255)
        case .breathing: return .teal
        case .alerting: return .orange
        case .resting, .overworking: return .red
        case .paused: return .gray
        }
    }

    @MainActor
    private func prepareCache() {
        let color = trayIconConfig.1
        let state = appState.currentState
        let pet = appState.selectedPet
        let useClassic = appState.useClassicTrayIcon
        
        // 只有当颜色、状态、宠物或深浅色主题发生变化时才重新生成缓存
        guard lastCachedState != state || lastCachedColor != color || lastCachedPet != pet || lastCachedColorScheme != colorScheme || lastCachedUseClassic != useClassic || frameCache.isEmpty else { return }
        
        frameCache.removeAll()
        
        let isW = (state == .working || state == .alerting || state == .overworking)
        let stateColor = robotLedColor
        
        for i in 0..<5 {
            if useClassic {
                if let img = loadAndPrepareImage(name: "\(i)", color: color, isTemplate: (state == .working || state == .idle)) {
                    frameCache[i] = img
                }
            } else {
                let now = TimeInterval(i) * 0.2
                let canvas: AnyView = {
                    switch appState.selectedPet {
                    case .clawd: return AnyView(ClawdCanvasView(pose: .rest, height: 18, isWalking: isW, now: now))
                    case .panda: return AnyView(PandaCanvasView(pose: .rest, height: 18, isWalking: isW, now: now))
                    case .pika: return AnyView(PikaCanvasView(pose: .rest, height: 18, isWalking: isW, now: now))
                    }
                }()
                
                // 使用小圆点指示状态（对所有宠物生效，包括 Robot）
                let indicator = Circle().fill(stateColor).frame(width: 4, height: 4)
                let composed = HStack(spacing: 2) {
                    canvas
                    indicator
                }
                let renderer = ImageRenderer(content: AnyView(composed))
                
                renderer.scale = NSScreen.main?.backingScaleFactor ?? 2.0
                if let cgImage = renderer.cgImage {
                    let logicalWidth = CGFloat(cgImage.width) / renderer.scale
                    let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: logicalWidth, height: 18))
                    nsImage.isTemplate = false // 全彩像素
                    frameCache[i] = nsImage
                }
            }
        }
        
        // 2. 预加载静态帧 (Frame 0)
        staticCache = frameCache[0]
        
        lastCachedState = state
        lastCachedColor = color
        lastCachedPet = pet
        lastCachedColorScheme = colorScheme
        lastCachedUseClassic = useClassic
        #if DEBUG
        print("💾 Tray icon cache refreshed for state: \(state) pet: \(pet.rawValue) classic: \(useClassic)")
        #endif
    }

    private func loadAndPrepareImage(name: String, color: NSColor, isTemplate: Bool) -> NSImage? {
        // In Xcode targets, images in xcassets are available via NSImage(named:)
        guard let image = NSImage(named: "RunningCat\(name)") else { return nil }
        
        let aspectRatio = image.size.width / image.size.height
        let targetHeight: CGFloat = 18.0
        let targetWidth = targetHeight * aspectRatio
        
        let resized = resizeImage(image, to: NSSize(width: targetWidth, height: targetHeight))
        
        if isTemplate {
            resized.isTemplate = true
            return resized
        } else {
            return tintNSImage(resized, with: color)
        }
    }

    private func resizeImage(_ image: NSImage, to size: NSSize) -> NSImage {
        let newImage = NSImage(size: size)
        newImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size), from: NSRect(origin: .zero, size: image.size), operation: .sourceOver, fraction: 1.0)
        newImage.unlockFocus()
        return newImage
    }

    private func tintNSImage(_ image: NSImage, with color: NSColor) -> NSImage {
        let tintedImage = NSImage(size: image.size)
        tintedImage.lockFocus()
        // Use a non-dynamic color space resolution just in case
        if let resolvedColor = color.usingColorSpace(.sRGB) {
            resolvedColor.set()
        } else {
            color.set()
        }
        let imageRect = NSRect(origin: .zero, size: image.size)
        imageRect.fill()
        image.draw(in: imageRect, from: NSRect(origin: .zero, size: image.size), operation: .destinationIn, fraction: 1.0)
        tintedImage.unlockFocus()
        tintedImage.isTemplate = false
        return tintedImage
    }
}

@main
struct MeowOutApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState = AppState()
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("isQuickToolsExpanded") private var isQuickToolsExpanded = false
    @State private var isHoveredToggle = false

    var body: some Scene {
        MenuBarExtra {
            VStack(spacing: 0) {
                menuContent
            }
            .frame(width: 280)
            .background(MenuVisualEffectView().ignoresSafeArea())
        } label: {
            TrayIconView(appState: appState)
                .background(WindowOpener())
                .onAppear {
                    appDelegate.appState = appState
                    appDelegate.tryStartEngine()
                    appState.initializeKeyboardShortcuts()
                    MemosPanelController.shared.configure(appState: appState)
                    QuickMemoPanelController.shared.configure(appState: appState)
                    MemosBrowserWindowController.shared.configure(appState: appState)
                    ClipboardPanelController.shared.configure(appState: appState)
                    QueueProcessor.shared.start()
                    ClipboardMonitorService.shared.start()
                }
                .onChange(of: appState.language) { _, _ in
                    // Force engine restart if language changes to pick up new strings
                    appDelegate.tryStartEngine()
                    ClipboardPanelController.shared.configure(appState: appState)
                }
        }
        .environment(appState)
        .menuBarExtraStyle(.window)

        Window(I18n.localized("settings_window_title", language: appState.language), id: "settings") {
            SettingsView(state: appState)
        }
        .windowResizability(.contentSize)
        .environment(appState)

        Window(I18n.localized("settings_tab_statistics", language: appState.language), id: "statistics") {
            StatsView(state: appState)
        }
        .windowResizability(.contentSize)
        .environment(appState)

        Window(I18n.localized("menu_breathing", language: appState.language), id: "breathing") {
            BreathingView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .environment(appState)

        Window(I18n.localized("menu_toolbox_2fa", language: appState.language), id: "meow2fa") {
            Meow2FAMainView()
                .background(Color.clear)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 380, height: 600)
        .environment(appState)

        Window(I18n.localized("keydrop_manager_title", language: appState.language), id: "snippet-manager") {
            SnippetManagerView()
        }
        .windowResizability(.automatic)
        .defaultSize(width: 800, height: 600)
        .environment(appState)
    }

    @ViewBuilder
    private var menuContent: some View {
        VStack(spacing: 8) {
            // Card 1: Dashboard & Pause Controls
            MenuDashboardCard(appState: appState)
            
            // Card 2: Tools & Shortcuts
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    let topTools = Array(appState.quickTools.prefix(2))
                    if topTools.isEmpty {
                        Text(I18n.localized("menu_shortcuts_empty", language: appState.language))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        ForEach(topTools) { tool in
                            renderToolTile(tool)
                        }
                        if topTools.count < 2 {
                            Spacer()
                        }
                    }
                }
                
                if appState.quickTools.count > 2 {
                    if isQuickToolsExpanded {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                            let remainingTools = Array(appState.quickTools.dropFirst(2))
                            ForEach(remainingTools) { tool in
                                renderSmallToolTile(tool)
                            }
                        }
                    }
                    
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            isQuickToolsExpanded.toggle()
                        }
                    } label: {
                        HStack {
                            Spacer()
                            Text(isQuickToolsExpanded ? "^ 收起" : "v 展开快捷应用")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.primary.opacity(0.6))
                            Spacer()
                        }
                        .padding(.vertical, 6)
                        .background(Color.primary.opacity(isHoveredToggle ? 0.08 : 0.04))
                        .cornerRadius(6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { h in isHoveredToggle = h }
                }
            }
            .padding(12)
            .background(
                colorScheme == .dark
                    ? Color.black.opacity(0.25)
                    : Color.white.opacity(0.85)
            )
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 5, x: 0, y: 1.5)
            

            // Card 4: System Actions
            VStack(spacing: 0) {
                MenuRowButton(
                    title: I18n.localized("menu_settings", language: appState.language),
                    icon: "⚙️",
                    iconColor: .secondary,
                    hasBadge: UpdateChecker.shared.hasPendingUpdate
                ) {
                    NotificationCenter.default.post(name: NSNotification.Name("OpenSettingsWindow"), object: nil)
                }
                
                Divider().background(Color.primary.opacity(0.05)).padding(.horizontal, 14)
                
                MenuRowButton(
                    title: I18n.localized("menu_quit", language: appState.language),
                    icon: "⏻",
                    iconColor: .red,
                    showChevron: false
                ) {
                    NSApplication.shared.terminate(nil)
                }
            }
            .background(
                colorScheme == .dark
                    ? Color.black.opacity(0.25)
                    : Color.white.opacity(0.85)
            )
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 5, x: 0, y: 1.5)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func renderToolTile(_ tool: QuickTool) -> some View {
        let descriptor = QuickToolActionResolver.descriptor(for: tool, appState: appState)
        let launchSubtitle = I18n.localized("menu_shortcuts_launch", language: appState.language)

        ControlTileButton(
            title: descriptor.displayName,
            subtitleActive: descriptor.state?.subtitle ?? launchSubtitle,
            subtitleInactive: descriptor.state?.subtitle ?? launchSubtitle,
            iconEmoji: descriptor.iconText ?? "🚀",
            isActive: descriptor.state?.isActive ?? false,
            action: {
                if descriptor.behavior == .launch || descriptor.id != BuiltInToolType.keepAwake.rawValue {
                    dismissMenu()
                }
                descriptor.execute()
            }
        )
    }

    @ViewBuilder
    private func renderSmallToolTile(_ tool: QuickTool) -> some View {
        let descriptor = QuickToolActionResolver.descriptor(for: tool, appState: appState)

        Button {
            dismissMenu()
            descriptor.execute()
        } label: {
            VStack(spacing: 4) {
                if let iconText = descriptor.iconText {
                    Text(iconText).font(.system(size: 18))
                } else if let path = descriptor.appPath {
                    AppIconView(path: path)
                }
                Text(descriptor.displayName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.8))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(10)
            .overlay(alignment: .topTrailing) {
                if descriptor.state?.isActive == true {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                        .offset(x: -4, y: 4)
                }
            }
        }
        .buttonStyle(.plain)
        .help(descriptor.displayName)
    }

    private func dismissMenu() {
        NSApp.windows.forEach { window in
            if window.styleMask.contains(.nonactivatingPanel) && 
               window.isVisible && 
               abs(window.frame.width - 280) < 2 {
                window.orderOut(nil)
            }
        }
    }
}

// MARK: - Component Views

struct QuickPauseButton: View {
    let title: String
    let action: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button {
            dismissMenu()
            action()
        } label: {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(isHovered ? Color.orange.opacity(0.12) : Color.primary.opacity(0.06))
                .foregroundColor(isHovered ? .orange : .primary.opacity(0.8))
                .cornerRadius(6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private func dismissMenu() {
        NSApp.windows.forEach { window in
            if window.styleMask.contains(.nonactivatingPanel) && 
               window.isVisible && 
               abs(window.frame.width - 280) < 2 {
                window.orderOut(nil)
            }
        }
    }
}

struct ControlTileButton: View {
    let title: String
    let subtitleActive: String
    let subtitleInactive: String
    let iconEmoji: String
    let isActive: Bool
    let action: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .center, spacing: 6) {
                Text(iconEmoji)
                    .font(.system(size: 24))
                    .frame(height: 26)
                
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(isActive ? .white : .primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .center)
            .frame(height: 72)
            .background {
                if isActive {
                    LinearGradient(
                        colors: [Color(red: 255/255, green: 159/255, blue: 67/255), Color(red: 255/255, green: 140/255, blue: 26/255)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                } else {
                    Color.primary.opacity(isHovered ? 0.08 : 0.04)
                }
            }
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isActive ? Color.orange.opacity(0.2) : Color.primary.opacity(0.06), lineWidth: 0.5)
            )
            .shadow(color: isActive ? Color.orange.opacity(0.2) : Color.black.opacity(0.04), radius: isActive ? 5 : 3, x: 0, y: isActive ? 2 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct MenuRowButton: View {
    let title: String
    let icon: String
    var iconColor: Color = .primary.opacity(0.8)
    var hasBadge: Bool = false
    var showChevron: Bool = true
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button {
            dismissMenu()
            action()
        } label: {
            HStack(spacing: 8) {
                Text(icon)
                    .font(.system(size: 13))
                    .frame(width: 20, alignment: .center)
                    .foregroundColor(iconColor)
                
                Text(title)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.primary)
                
                if hasBadge {
                    UpdateBadge()
                }
                
                Spacer()
                
                if showChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.primary.opacity(0.15))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8.5)
            .background(isHovered ? Color.primary.opacity(0.04) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
    
    private func dismissMenu() {
        NSApp.windows.forEach { window in
            if window.styleMask.contains(.nonactivatingPanel) && 
               window.isVisible && 
               abs(window.frame.width - 280) < 2 {
                window.orderOut(nil)
            }
        }
    }
}

struct MenuDashboardCard: View {
    @Bindable var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 0) {
                // Left Column: Goal
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text("🎯")
                            .font(.system(size: 13))
                        Text(I18n.localized("stats_todays_goal", language: appState.language))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        Button(action: {
                            NSApp.windows.forEach { window in
                                if window.styleMask.contains(.nonactivatingPanel) && 
                                   window.isVisible && 
                                   abs(window.frame.width - 280) < 2 {
                                    window.orderOut(nil)
                                }
                            }
                            NSApp.activate(ignoringOtherApps: true)
                            (NSApp.delegate as? AppDelegate)?.tryStartEngine()
                            NotificationCenter.default.post(name: NSNotification.Name("OpenStatisticsWindow"), object: nil)
                        }) {
                            Image(systemName: "chart.bar.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                        .help(I18n.localized("settings_tab_statistics", language: appState.language))
                    }

                    let goalProgress = min(1.0, appState.totalWorkToday / (Double(appState.dailyWorkGoal) * 3600))
                    HStack(alignment: .center, spacing: 10) {
                        CapsuleProgressView(value: goalProgress)

                        Text("\(String(format: "%.1f", appState.totalWorkToday / 3600)) / \(appState.dailyWorkGoal).0 h")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 12)

                Divider()
                    .frame(height: 40)
                    .background(Color.primary.opacity(0.05))

                // Right Column: Session
                VStack(alignment: .center, spacing: 0) {
                    let sessionProgress = min(1.0, appState.workElapsed / appState.maxWorkTime)
                    CircularProgressView(
                        value: sessionProgress,
                        text: "\(Int(appState.workElapsed / 60))m"
                    )
                }
                .frame(width: 56)
                .padding(.leading, 12)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Water Row
            HStack(spacing: 6) {
                Text("💧")
                    .font(.system(size: 13))
                Text(I18n.localized("water_today_label", language: appState.language))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(.primary)
                Spacer()
                Text("\(appState.todayWaterCups)/\(appState.dailyWaterGoal)")
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.blue)
                Button(action: {
                    appState.todayWaterCups += 1
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
            
            Divider()
                .background(Color.primary.opacity(0.05))
                .padding(.horizontal, 14)
            
            // Pause Row
            if appState.currentState == .paused {
                HStack(spacing: 8) {
                    Text("⏸")
                        .font(.system(size: 12))
                    Text(I18n.localizedFormat("menu_paused_label", language: appState.language, Int64(appState.pauseRemaining / 60)))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(.primary)
                    Spacer()
                    Button {
                        appState.currentState = .working
                        appState.pauseRemaining = 0
                        dismissMenu()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 8, weight: .bold))
                            Text(I18n.localized("menu_resume", language: appState.language))
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundColor(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.12))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            } else {
                HStack(spacing: 8) {
                    Text("⏸")
                        .font(.system(size: 12))
                    Text(I18n.localized("menu_pause", language: appState.language))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(.primary)
                    Spacer()
                    HStack(spacing: 4) {
                        QuickPauseButton(title: "15m") { pause(minutes: 15) }
                        QuickPauseButton(title: "30m") { pause(minutes: 30) }
                        QuickPauseButton(title: "1h") { pause(minutes: 60) }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
        }
        .onAppear {
            appState.checkAndResetWaterIfNewDay()
        }
        .background(
            colorScheme == .dark
                ? Color.black.opacity(0.25)
                : Color.white.opacity(0.85)
        )
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 5, x: 0, y: 1.5)
    }
    
    private func pause(minutes: Int) {
        appState.pauseRemaining = TimeInterval(minutes * 60)
        appState.currentState = .paused
    }
    
    private func dismissMenu() {
        NSApp.windows.forEach { window in
            if window.styleMask.contains(.nonactivatingPanel) && 
               window.isVisible && 
               abs(window.frame.width - 280) < 2 {
                window.orderOut(nil)
            }
        }
    }
}

// MARK: - Internal Progress Components

struct CapsuleProgressView: View {
    var value: Double // 0.0 to 1.0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.15))
                    .frame(height: 7)
                
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.orange, Color(red: 255/255, green: 173/255, blue: 51/255)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(7, geometry.size.width * value), height: 7)
                    .shadow(color: .orange.opacity(0.3), radius: 3, x: 0, y: 0)
            }
        }
        .frame(height: 7)
    }
}

struct CircularProgressView: View {
    var value: Double // 0.0 to 1.0
    var text: String
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.15), lineWidth: 3.5)
            
            Circle()
                .trim(from: 0, to: value)
                .stroke(Color.orange, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            
            Text(text)
                .font(.system(size: 10, weight: .bold))
        }
        .frame(width: 44, height: 44)
    }
}

struct MenuVisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = .popover
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct AppIconView: View {
    let path: String
    @State private var icon: NSImage?

    var body: some View {
        Group {
            if let icon = icon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
            } else {
                Image(systemName: "app.dashed")
                    .resizable()
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 24, height: 24)
        .onAppear {
            DispatchQueue.global(qos: .userInitiated).async {
                let fetchedIcon = NSWorkspace.shared.icon(forFile: path)
                DispatchQueue.main.async {
                    self.icon = fetchedIcon
                }
            }
        }
    }
}
