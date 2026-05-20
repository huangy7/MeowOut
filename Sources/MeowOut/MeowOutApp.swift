import SwiftUI
import AppKit

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var appState: AppState?
    var monitor: ActivityMonitor?
    private var isStarted = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 对于托盘应用，确保激活策略正确
        NSApp.setActivationPolicy(.accessory)
    }

    func tryStartEngine() {
        guard let state = appState, !isStarted else { return }
        self.monitor = ActivityMonitor(appState: state)
        self.monitor?.start()
        CatOverlayController.shared.start(appState: state)
        isStarted = true
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
    }
}

/// 独立的图标视图，最小化重绘范围
struct TrayIconView: View {
    @Bindable var appState: AppState
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

    var body: some View {
        Group {
            if let image = currentImage {
                Image(nsImage: image)
            } else {
                Image(systemName: trayIconConfig.0)
            }
        }
        .onReceive(animationTimer) { _ in
            if appState.isWalking {
                appState.currentFrameIndex = (appState.currentFrameIndex + 1) % 5
            }
        }
        .onAppear {
            prepareCache()
        }
        .onChange(of: appState.currentState) { _, _ in prepareCache() }
    }
    
    private var currentImage: NSImage? {
        if appState.isWalking {
            return frameCache[appState.currentFrameIndex]
        } else {
            return staticCache
        }
    }
    
    private func prepareCache() {
        let color = trayIconConfig.1
        let state = appState.currentState
        
        // 只有当颜色或状态发生关键变化时才重新生成缓存
        guard lastCachedState != state || lastCachedColor != color || frameCache.isEmpty else { return }
        
        // 1. 预加载 5 帧奔跑动画
        for i in 0..<5 {
            if let img = loadAndPrepareImage(name: "\(i)", color: color, isTemplate: (state == .working || state == .idle)) {
                frameCache[i] = img
            }
        }
        
        // 2. 预加载静态帧 (Frame 0)
        staticCache = frameCache[0]
        
        lastCachedState = state
        lastCachedColor = color
        print("💾 Tray icon cache refreshed for state: \(state)")
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

    var body: some Scene {
        MenuBarExtra {
            VStack(spacing: 0) {
                WindowOpener()
                menuContent
            }
            .frame(width: 280)
            .background(VisualEffectView().ignoresSafeArea())
        } label: {
            TrayIconView(appState: appState)
                .onAppear {
                    appDelegate.appState = appState
                    appDelegate.tryStartEngine()
                }
                .onChange(of: appState.language) { _, _ in
                    // Force engine restart if language changes to pick up new strings
                    appDelegate.tryStartEngine()
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

        Window("正念练习", id: "breathing") {
            BreathingView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .environment(appState)
    }

    @ViewBuilder
    private var menuContent: some View {
        VStack(spacing: 0) {
            // Section 1: Status
            MenuDashboardCard(appState: appState)

            Divider()

            VStack(spacing: 4) {
                // Section 2: Actions
                if appState.currentState == .paused {
                    HStack {
                        Text(I18n.localizedFormat("menu_paused_label", language: appState.language, Int64(appState.pauseRemaining / 60)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            appState.currentState = .working
                            appState.pauseRemaining = 0
                            
                            // Dismiss menu
                            NSApp.windows.forEach { window in
                                if window.styleMask.contains(.nonactivatingPanel) && 
                                   window.isVisible && 
                                   abs(window.frame.width - 280) < 2 {
                                    window.orderOut(nil)
                                }
                            }
                        } label: {
                            Image(systemName: "play.fill")
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                } else {
                    HStack {
                        Label(I18n.localized("menu_pause", language: appState.language), systemImage: "pause.fill")
                        Spacer()
                        HStack(spacing: 6) {
                            QuickPauseButton(title: "15m") { pause(minutes: 15) }
                            QuickPauseButton(title: "30m") { pause(minutes: 30) }
                            QuickPauseButton(title: "1h") { pause(minutes: 60) }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }

                Divider()

                // Section 3: Features
                VStack(spacing: 0) {
                    menuButton(title: I18n.localized("menu_breathing", language: appState.language), icon: "wind") {
                        NotificationCenter.default.post(name: NSNotification.Name("OpenBreathingWindow"), object: nil)
                    }
                    
                    menuButton(title: I18n.localized("settings_tab_statistics", language: appState.language), icon: "chart.bar.xaxis") {
                        NSApp.activate(ignoringOtherApps: true)
                        appDelegate.tryStartEngine()
                        NotificationCenter.default.post(name: NSNotification.Name("OpenStatisticsWindow"), object: nil)
                    }
                }

                Divider()

                // Section 4: System
                VStack(spacing: 0) {
                    menuButton(title: I18n.localized("menu_settings", language: appState.language), icon: "gearshape") {
                        NotificationCenter.default.post(name: NSNotification.Name("OpenSettingsWindow"), object: nil)
                    }
                    
                    menuButton(title: I18n.localized("menu_quit", language: appState.language), icon: "power") {
                        NSApplication.shared.terminate(nil)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func menuButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        ButtonView(title: title, icon: icon, action: action)
    }

    private func pause(minutes: Int) {
        appState.pauseRemaining = TimeInterval(minutes * 60)
        appState.currentState = .paused
    }
}

struct ButtonView: View {
    let title: String
    let icon: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button {
            // macOS standard: dismiss menu before or during action
            dismissMenu()
            action()
        } label: {
            HStack {
                Image(systemName: icon)
                    .frame(width: 20)
                Text(title)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private func dismissMenu() {
        // For .window style MenuBarExtra, we manually hide the window
        // The menu window is typically a nonactivatingPanel with our fixed width
        NSApp.windows.forEach { window in
            if window.styleMask.contains(.nonactivatingPanel) && 
               window.isVisible && 
               abs(window.frame.width - 280) < 2 {
                window.orderOut(nil)
            }
        }
    }
}

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
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isHovered ? Color.orange.opacity(0.15) : Color.secondary.opacity(0.1))
                .foregroundColor(isHovered ? .orange : .primary)
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

struct MenuDashboardCard: View {
    @Bindable var appState: AppState
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 0) {
                // Left Column: Goal
                VStack(alignment: .leading, spacing: 8) {
                    Label {
                        Text(I18n.localized("stats_todays_goal", language: appState.language))
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                    } icon: {
                        Image(systemName: "target")
                            .font(.system(size: 14, weight: .ultraLight))
                            .foregroundStyle(.orange)
                    }

                    let goalProgress = min(1.0, appState.totalWorkToday / (Double(appState.dailyWorkGoal) * 3600))
                    HStack(alignment: .center, spacing: 10) {
                        CapsuleProgressView(value: goalProgress)

                        Text("\(String(format: "%.1f", appState.totalWorkToday / 3600)) / \(appState.dailyWorkGoal).0 h")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 16)

                Divider()
                    .frame(height: 44)

                // Right Column: Session
                VStack(alignment: .center, spacing: 0) {
                    let sessionProgress = min(1.0, appState.workElapsed / appState.maxWorkTime)
                    CircularProgressView(
                        value: sessionProgress,
                        text: "\(Int(appState.workElapsed / 60))m"
                    )
                }
                .frame(width: 70)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(width: 280, alignment: .leading)

            // Water Row
            HStack(spacing: 8) {
                Image(systemName: "drop.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.blue)
                Text(I18n.localized("water_today_label", language: appState.language))
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text("\(appState.todayWaterCups)/\(appState.dailyWaterGoal)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
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
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .onAppear {
            appState.checkAndResetWaterIfNewDay()
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
                    .frame(height: 8)
                
                Capsule()
                    .fill(Color.orange)
                    .frame(width: max(8, geometry.size.width * value), height: 8)
                    .shadow(color: .orange.opacity(0.3), radius: 4, x: 0, y: 0)
            }
        }
        .frame(height: 8)
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
