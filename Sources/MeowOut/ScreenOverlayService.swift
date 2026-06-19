import AppKit
import SwiftUI

@MainActor
public final class ScreenOverlayService {
    public static let shared = ScreenOverlayService()
    
    private var windows: [NSPanel] = []
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var appState: AppState?
    private var currentMode: ScreenOverlayMode?
    
    private var holdStartTime: Date?
    private var exitTimer: Timer?
    private var autoExitWorkItem: DispatchWorkItem?
    private var windowObservers: [NSObjectProtocol] = []
    private var systemObservers: [NSObjectProtocol] = []
    
    private init() {
        // 监听系统级事件：锁屏、会话切换、显示器休眠——这些情况下系统可能关闭遮盖窗口但不通知 event tap
        let workspaceNC = NSWorkspace.shared.notificationCenter
        
        // 系统即将休眠
        systemObservers.append(
            workspaceNC.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                self?.stop()
            }
        )
        // 显示器休眠（独立于系统休眠）
        systemObservers.append(
            workspaceNC.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
                self?.stop()
            }
        )
        // 会话失活：包含系统自动锁屏、快速用户切换
        systemObservers.append(
            workspaceNC.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                self?.stop()
            }
        )
    }
    
    public func start(mode: ScreenOverlayMode, appState: AppState) {
        guard windows.isEmpty else { return }
        self.appState = appState
        self.currentMode = mode
        
        // 1. Check Accessibility Permission
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else {
            print("Screen Overlay (\(mode)) requires Accessibility permission.")
            resetState(for: mode)
            return
        }
        
        // 2. Create overlay windows for each connected screen
        let screens = NSScreen.screens.isEmpty ? [NSScreen.main].compactMap { $0 } : NSScreen.screens
        for (index, screen) in screens.enumerated() {
            let panel = OverlayPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.backgroundColor = .black
            panel.level = .screenSaver // Above Menu Bar, Dock, and other overlays
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.hasShadow = false
            
            // Only show instructions on the primary screen (index 0) to keep secondary screens clear
            let showInstructions = (index == 0)
            let contentView = NSHostingView(
                rootView: ScreenOverlayView(
                    appState: appState,
                    mode: mode,
                    showInstructions: showInstructions
                )
            )
            panel.contentView = contentView
            windows.append(panel)
        }
        
        NSApp.activate(ignoringOtherApps: true)
        windows.first?.makeKeyAndOrderFront(nil)
        windows.dropFirst().forEach { $0.orderFrontRegardless() }
        
        // 监听遮盖窗口意外关闭（如 ESC 短按绕过了拦截），确保 event tap 同步停止
        for window in windows {
            let observer = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                guard let self = self, self.currentMode != nil else { return }
                self.stop()
            }
            windowObservers.append(observer)
        }
        
        // 3. Start global event tap to lock inputs
        do {
            try startEventTap()
        } catch {
            print("Failed to start event tap for Screen Overlay: \(error)")
            stop()
            return
        }
        
        NSCursor.hide()
        
        // 4. Auto-timeout after 10 minutes (600 seconds) ONLY for screen cleaning
        if mode == .screenCleaning {
            let workItem = DispatchWorkItem { [weak self] in
                DispatchQueue.main.async {
                    self?.stop()
                }
            }
            autoExitWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 600, execute: workItem)
        }
    }
    
    public func stop() {
        // 先移除 observer，防止 close() 触发回调再次调用 stop()
        windowObservers.forEach { NotificationCenter.default.removeObserver($0) }
        windowObservers.removeAll()
        
        windows.forEach { $0.close() }
        windows.removeAll()
        
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        
        resetExitTimer()
        autoExitWorkItem?.cancel()
        autoExitWorkItem = nil
        
        NSCursor.unhide()
        
        if let mode = currentMode {
            currentMode = nil
            resetState(for: mode)
        }
        self.appState = nil
    }
    
    private func resetState(for mode: ScreenOverlayMode) {
        guard let state = appState else { return }
        switch mode {
        case .screenCleaning:
            state.isScreenCleaningActive = false
        }
    }
    
    private func startEventTap() throws {
        // Intercept all keyboard, mouse movement, clicks, drags, and scroll wheel events
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) |
            CGEventMask(1 << CGEventType.keyUp.rawValue) |
            CGEventMask(1 << CGEventType.flagsChanged.rawValue) |
            CGEventMask(1 << CGEventType.leftMouseDown.rawValue) |
            CGEventMask(1 << CGEventType.leftMouseUp.rawValue) |
            CGEventMask(1 << CGEventType.rightMouseDown.rawValue) |
            CGEventMask(1 << CGEventType.rightMouseUp.rawValue) |
            CGEventMask(1 << CGEventType.mouseMoved.rawValue) |
            CGEventMask(1 << CGEventType.leftMouseDragged.rawValue) |
            CGEventMask(1 << CGEventType.rightMouseDragged.rawValue) |
            CGEventMask(1 << CGEventType.scrollWheel.rawValue)
            
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let service = Unmanaged<ScreenOverlayService>.fromOpaque(refcon).takeUnretainedValue()
                
                if type == .keyDown || type == .keyUp {
                    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                    if keyCode == 53 { // ESC Key code
                        let isDown = (type == .keyDown)
                        DispatchQueue.main.async {
                            service.handleEscKey(isDown: isDown)
                        }
                    }
                }
                
                // Return nil to discard the event and lock input globally
                return nil
            },
            userInfo: selfPtr
        ) else {
            throw NSError(
                domain: "ScreenOverlayService",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Unable to start screen overlay event tap."]
            )
        }
        
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let runLoopSource = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
    }
    
    private func handleEscKey(isDown: Bool) {
        if isDown {
            if holdStartTime == nil {
                holdStartTime = Date()
                startExitTimer()
            }
        } else {
            resetExitTimer()
        }
    }
    
    private func startExitTimer() {
        exitTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.checkExitProgress()
            }
        }
    }
    
    private func checkExitProgress() {
        guard let start = holdStartTime else { return }
        let duration = Date().timeIntervalSince(start)
        let progress = min(duration / 2.0, 1.0)
        
        NotificationCenter.default.post(name: NSNotification.Name("screenOverlayProgress"), object: progress)
        
        if progress >= 1.0 {
            stop()
        }
    }
    
    private func resetExitTimer() {
        exitTimer?.invalidate()
        exitTimer = nil
        holdStartTime = nil
        NotificationCenter.default.post(name: NSNotification.Name("screenOverlayProgress"), object: 0.0)
    }
}
