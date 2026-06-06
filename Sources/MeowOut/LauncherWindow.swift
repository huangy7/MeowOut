import AppKit
import SwiftUI

enum LauncherWindowSelectionGeometry {
    static func sectorIndex(atWindowPoint point: CGPoint, in windowSize: CGSize, count: Int) -> Int? {
        let ringOrigin = CGPoint(
            x: (windowSize.width - LauncherVisualMetrics.ringSize) / 2,
            y: (windowSize.height - LauncherVisualMetrics.ringSize) / 2
        )
        let ringPoint = CGPoint(x: point.x - ringOrigin.x, y: point.y - ringOrigin.y)
        return LauncherSelectionGeometry.sectorIndex(
            at: ringPoint,
            in: CGSize(width: LauncherVisualMetrics.ringSize, height: LauncherVisualMetrics.ringSize),
            count: count
        )
    }
}

@MainActor
public final class LauncherWindow: NSPanel {
    public static let shared = LauncherWindow()
    
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?
    private var releaseEventMonitor: Any?
    private var releasePollTimer: Timer?
    private var appState: AppState?
    private var releaseToLaunchModifier: AppState.LauncherTriggerModifier?
    private var lastScrollTime: TimeInterval = 0
    
    // We will reference the hosting view's model/state if needed
    // For now we can communicate through notifications or a Shared State
    
    public override func scrollWheel(with event: NSEvent) {
        guard let state = appState else {
            super.scrollWheel(with: event)
            return
        }
        
        let delta = event.scrollingDeltaY
        if abs(delta) > 0.5 {
            let now = Date().timeIntervalSince1970
            if now - lastScrollTime > 0.15 {
                lastScrollTime = now
                let direction = delta > 0 ? -1 : 1
                let count = state.launcherRings.count
                if count > 0 {
                    let nextIndex = (state.currentLauncherRingIndex + direction + count) % count
                    state.currentLauncherRingIndex = nextIndex
                    // Play a soft haptic tick
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                }
            }
        }
    }
    
    private init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: LauncherVisualMetrics.windowSize, height: LauncherVisualMetrics.windowSize),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        
        self.level = .popUpMenu
        self.isFloatingPanel = true
        self.worksWhenModal = true
        self.hidesOnDeactivate = false
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = LauncherVisualMetrics.usesSystemPanelShadow
    }
    
    public func show(
        at mouseLocation: CGPoint,
        appState: AppState,
        releaseToLaunchModifier: AppState.LauncherTriggerModifier? = nil
    ) {
        self.appState = appState
        self.releaseToLaunchModifier = releaseToLaunchModifier
        
        let view = LauncherView(appState: appState, onClose: { [weak self] in
            self?.close()
        })
        
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: LauncherVisualMetrics.windowSize, height: LauncherVisualMetrics.windowSize)
        if #available(macOS 13.0, *) { hostingView.sizingOptions = [] }
        self.contentView = hostingView
        
        // Position window centered at mouse
        var panelRect = self.frame
        panelRect.origin.x = mouseLocation.x - panelRect.width / 2
        panelRect.origin.y = mouseLocation.y - panelRect.height / 2
        
        // Constrain to screen boundaries
        let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main
        if let screenFrame = screen?.visibleFrame {
            if panelRect.minX < screenFrame.minX { panelRect.origin.x = screenFrame.minX }
            if panelRect.maxX > screenFrame.maxX { panelRect.origin.x = screenFrame.maxX - panelRect.width }
            if panelRect.minY < screenFrame.minY { panelRect.origin.y = screenFrame.minY }
            if panelRect.maxY > screenFrame.maxY { panelRect.origin.y = screenFrame.maxY - panelRect.height }
        }
        
        self.setFrame(panelRect, display: true)
        self.orderFrontRegardless()
        
        setupMonitors()
    }
    
    public override func close() {
        self.orderOut(nil)
        removeMonitors()
        releaseToLaunchModifier = nil
    }
    
    public func triggerHoveredSector() {
        if let launcherView = self.contentView as? NSHostingView<LauncherView> {
            launcherView.rootView.triggerHoveredSector()
        }
    }

    public func triggerSectorUnderMouseAndClose() {
        guard let appState else {
            close()
            return
        }

        let descriptors = currentDescriptors(appState: appState)
        let point = contentView?.convert(mouseLocationOutsideOfEventStream, from: nil) ?? mouseLocationOutsideOfEventStream
        if let index = LauncherWindowSelectionGeometry.sectorIndex(
            atWindowPoint: point,
            in: contentView?.bounds.size ?? frame.size,
            count: descriptors.count
        ), index < descriptors.count {
            descriptors[index].execute()
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
        }

        close()
    }
    
    private func setupMonitors() {
        removeMonitors()
        
        // Close if click outside window
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.close()
            }
        }

        releaseEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.handleReleaseEvent(flags: event.modifierFlags)
            }
        }
        
        // Also capture escape key locally
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self = self else { return event }
            if event.keyCode == 53 { // ESC
                self.close()
                return nil
            }
            if event.type == .flagsChanged {
                self.handleReleaseEvent(flags: event.modifierFlags)
            }
            return event
        }

        startReleasePollTimer()
    }
    
    private func removeMonitors() {
        if let global = globalEventMonitor {
            NSEvent.removeMonitor(global)
            globalEventMonitor = nil
        }
        if let local = localEventMonitor {
            NSEvent.removeMonitor(local)
            localEventMonitor = nil
        }
        if let release = releaseEventMonitor {
            NSEvent.removeMonitor(release)
            releaseEventMonitor = nil
        }
        releasePollTimer?.invalidate()
        releasePollTimer = nil
    }
    
    public override var canBecomeKey: Bool {
        return true
    }

    private func handleReleaseEvent(flags: NSEvent.ModifierFlags) {
        guard let modifier = releaseToLaunchModifier else { return }
        guard !isModifierPressed(flags, target: modifier) else { return }
        releaseToLaunchModifier = nil
        triggerSectorUnderMouseAndClose()
    }

    private func startReleasePollTimer() {
        releasePollTimer?.invalidate()
        guard releaseToLaunchModifier != nil else { return }

        releasePollTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let modifier = self.releaseToLaunchModifier else { return }
                guard !self.isModifierCurrentlyPressed(modifier) else { return }
                self.releaseToLaunchModifier = nil
                self.triggerSectorUnderMouseAndClose()
            }
        }
    }

    private func currentDescriptors(appState: AppState) -> [QuickToolActionDescriptor] {
        let rings = appState.launcherRings
        let ringIndex = appState.currentLauncherRingIndex
        guard ringIndex >= 0, ringIndex < rings.count else { return [] }
        return rings[ringIndex].tools.map {
            QuickToolActionResolver.descriptor(for: $0, appState: appState)
        }
    }

    private func isModifierPressed(_ flags: NSEvent.ModifierFlags, target: AppState.LauncherTriggerModifier) -> Bool {
        let rawFlags = flags.intersection(.deviceIndependentFlagsMask)
        switch target {
        case .option:
            return rawFlags.contains(.option)
        case .command:
            return rawFlags.contains(.command)
        case .shift:
            return rawFlags.contains(.shift)
        case .control:
            return rawFlags.contains(.control)
        }
    }

    private func isModifierCurrentlyPressed(_ target: AppState.LauncherTriggerModifier) -> Bool {
        let flags = CGEventSource.flagsState(.combinedSessionState)
        switch target {
        case .option:
            return flags.contains(.maskAlternate)
        case .command:
            return flags.contains(.maskCommand)
        case .shift:
            return flags.contains(.maskShift)
        case .control:
            return flags.contains(.maskControl)
        }
    }
}
