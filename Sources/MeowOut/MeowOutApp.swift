import SwiftUI
import AppKit

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var appState: AppState?
    var monitor: ActivityMonitor?
    private var isStarted = false

    func applicationDidFinishLaunching(_ notification: Notification) {
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
    }
}

/// 独立的图标视图，最小化重绘范围
struct TrayIconView: View {
    @Bindable var appState: AppState
    let trayIconConfig: (String, Color)
    let animationTimer = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()
    
    // 🖼️ 核心优化：图像缓存
    @State private var frameCache: [Int: NSImage] = [:]
    @State private var staticCache: NSImage?
    @State private var lastCachedState: AppPhase?
    @State private var lastCachedColor: Color?

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

    private func loadAndPrepareImage(name: String, color: Color, isTemplate: Bool) -> NSImage? {
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

    private func tintNSImage(_ image: NSImage, with color: Color) -> NSImage {
        guard let tintedImage = image.copy() as? NSImage else { return image }
        tintedImage.isTemplate = false
        tintedImage.lockFocus()
        let nsColor: NSColor = (color == .orange) ? .orange : (color == .red ? .red : .labelColor)
        nsColor.set()
        let imageRect = NSRect(origin: .zero, size: tintedImage.size)
        imageRect.fill(using: .sourceIn)
        tintedImage.unlockFocus()
        return tintedImage
    }
}

@main
struct MeowOutApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState = AppState()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra {
            let _ = { 
                appDelegate.appState = appState
                appDelegate.tryStartEngine()
            }()
            
            WindowOpener()
            menuContent
        } label: {
            TrayIconView(appState: appState, trayIconConfig: trayIconConfig)
        }
        .environment(appState)

        Window(I18n.localized("settings_window_title", language: appState.language), id: "settings") {
            SettingsView(state: appState)
        }
        .windowResizability(.contentSize)

        Window(I18n.localized("settings_tab_statistics", language: appState.language), id: "statistics") {
            StatsView(state: appState)
        }
        .windowResizability(.contentSize)
    }

    @ViewBuilder
    private var menuContent: some View {
        Text(I18n.localizedFormat("menu_today_label", language: appState.language, String(format: "%.1f", appState.totalWorkToday / 3600), Int64(appState.dailyWorkGoal)))
        Divider()
        if appState.currentState == .paused {
            Text(I18n.localizedFormat("menu_paused_label", language: appState.language, Int64(appState.pauseRemaining / 60)))
            Button(I18n.localized("menu_resume", language: appState.language)) {
                appState.currentState = .working
                appState.pauseRemaining = 0
            }
        } else {
            Text(I18n.localizedFormat("menu_work_label", language: appState.language, Int64(appState.workElapsed / 60)))
            Menu(I18n.localized("menu_pause", language: appState.language)) {
                Button(I18n.localized("menu_pause_15m", language: appState.language)) { pause(minutes: 15) }
                Button(I18n.localized("menu_pause_30m", language: appState.language)) { pause(minutes: 30) }
                Button(I18n.localized("menu_pause_1h", language: appState.language)) { pause(minutes: 60) }
            }
        }
        Divider()
        Menu(I18n.localized("menu_advanced", language: appState.language)) {
            Button(I18n.localized("menu_trigger_warning", language: appState.language)) { appState.workElapsed = appState.alertThreshold; appState.currentState = .alerting }
            Button(I18n.localized("menu_force_rest", language: appState.language)) { appState.workElapsed = appState.maxWorkTime; appState.restRemaining = appState.defaultRestTime; appState.currentState = .resting }
            Divider()
            Button(I18n.localized("menu_reset_timers", language: appState.language)) { appState.workElapsed = 0; appState.currentState = .working }
        }
        Divider()
        Button(I18n.localized("settings_tab_statistics", language: appState.language)) { 
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "statistics") 
        }
        Button(I18n.localized("menu_settings", language: appState.language)) { NotificationCenter.default.post(name: NSNotification.Name("OpenSettingsWindow"), object: nil) }
        .keyboardShortcut(",", modifiers: .command)
        Button(I18n.localized("menu_quit", language: appState.language)) { NSApplication.shared.terminate(nil) }
    }

    private var trayIconConfig: (String, Color) {
        switch appState.currentState {
        case .working: return ("cat.fill", .primary)
        case .alerting: return ("cat.fill", .orange)
        case .resting: return ("cat.fill", .red)
        case .paused: return ("pause.circle", .secondary)
        case .idle: return ("cat.fill", .secondary)
        }
    }

    private func pause(minutes: Int) {
        appState.pauseRemaining = TimeInterval(minutes * 60)
        appState.currentState = .paused
    }
}
