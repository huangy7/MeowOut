import AppKit
import Foundation

extension Notification.Name {
    static let launcherAccessibilityPermissionLost = Notification.Name("LauncherAccessibilityPermissionLost")
}

@MainActor
public final class LauncherTriggerService {
    public static let shared = LauncherTriggerService()

    private var appState: AppState?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var activationObserver: NSObjectProtocol?

    private var isKeyPressed = false
    private var triggerState = LauncherTriggerStateMachine()
    private var pressTimer: Timer?
    private var permissionWatchdog: Timer?

    private init() {}

    public func setAppState(_ appState: AppState) {
        self.appState = appState
    }

    public func start(appState: AppState) {
        self.appState = appState

        guard appState.launcherEnabled, appState.launcherTriggerMode == .advancedModifier else {
            stop()
            return
        }

        if activationObserver == nil {
            activationObserver = NotificationCenter.default.addObserver(forName: NSApplication.willBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self, let appState = self.appState else { return }
                    guard appState.launcherEnabled, appState.launcherTriggerMode == .advancedModifier else {
                        self.stop()
                        return
                    }
                    if AXIsProcessTrusted() {
                        if self.globalMonitor == nil {
                            self.setupMonitors()
                        }
                    } else if self.globalMonitor != nil {
                        self.removeEventMonitors()
                    }
                }
            }
        }

        if AXIsProcessTrusted() {
            setupMonitors()
            startWatchdog()
        } else {
            removeEventMonitors()
            stopWatchdog()
        }
    }
    
    public func stop() {
        removeEventMonitors()
        stopWatchdog()
        if let observer = activationObserver {
            NotificationCenter.default.removeObserver(observer)
            activationObserver = nil
        }
    }

    private func removeEventMonitors() {
        if let gm = globalMonitor {
            NSEvent.removeMonitor(gm)
            globalMonitor = nil
        }
        if let lm = localMonitor {
            NSEvent.removeMonitor(lm)
            localMonitor = nil
        }
        pressTimer?.invalidate()
        pressTimer = nil
        isKeyPressed = false
        triggerState.reset()
    }
    
    private func setupMonitors() {
        removeEventMonitors()
        
        let eventMask: NSEvent.EventTypeMask = [.flagsChanged]
        
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: eventMask) { [weak self] event in
            Task { @MainActor in
                self?.handleFlagsChanged(event)
            }
        }
        
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: eventMask) { [weak self] event in
            Task { @MainActor in
                self?.handleFlagsChanged(event)
            }
            return event
        }
    }
    
    private func handleFlagsChanged(_ event: NSEvent) {
        guard let state = appState, state.launcherEnabled, state.launcherTriggerMode == .advancedModifier else { return }
        
        let modifier = state.launcherTriggerKey
        let isNowPressed = checkModifierPressed(event.modifierFlags, target: modifier)
        
        if isNowPressed && !isKeyPressed {
            isKeyPressed = true
            handleKeyDown(state: state, at: event.timestamp)
        } else if !isNowPressed && isKeyPressed {
            isKeyPressed = false
            handleKeyUp(state: state, at: event.timestamp)
        }
    }
    
    private func checkModifierPressed(_ flags: NSEvent.ModifierFlags, target: AppState.LauncherTriggerModifier) -> Bool {
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
    
    private func handleKeyDown(state: AppState, at time: TimeInterval) {
        pressTimer?.invalidate()
        let actions = triggerState.keyDown(at: time, config: triggerConfiguration(for: state))
        perform(actions, state: state)

        pressTimer = Timer.scheduledTimer(withTimeInterval: state.launcherLongPressDelay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, let appState = self.appState else { return }
                let actions = self.triggerState.longPressTimerFired(
                    at: ProcessInfo.processInfo.systemUptime,
                    config: self.triggerConfiguration(for: appState)
                )
                self.perform(actions, state: appState)
            }
        }
    }
    
    private func handleKeyUp(state: AppState, at time: TimeInterval) {
        pressTimer?.invalidate()
        pressTimer = nil

        let actions = triggerState.keyUp(at: time, config: triggerConfiguration(for: state))
        perform(actions, state: state)
    }
    
    private func showLauncher(state: AppState) {
        LauncherWindow.shared.show(
            at: NSEvent.mouseLocation,
            appState: state,
            releaseToLaunchModifier: state.launcherClickToLaunch ? nil : state.launcherTriggerKey
        )
    }
    
    public func toggleLauncher() {
        guard let state = appState else { return }
        if LauncherWindow.shared.isVisible {
            LauncherWindow.shared.close()
        } else {
            showLauncher(state: state)
        }
    }
    
    private func triggerHoveredSectorAndClose(state: AppState) {
        LauncherWindow.shared.triggerHoveredSector()
        LauncherWindow.shared.close()
    }

    private func triggerConfiguration(for state: AppState) -> LauncherTriggerStateMachine.Configuration {
        LauncherTriggerStateMachine.Configuration(
            doubleClickToActivate: state.launcherDoubleClickToActivate,
            clickToLaunch: state.launcherClickToLaunch,
            longPressDelay: state.launcherLongPressDelay,
            doubleClickInterval: NSEvent.doubleClickInterval
        )
    }

    private func perform(_ actions: [LauncherTriggerStateMachine.Action], state: AppState) {
        for action in actions {
            switch action {
            case .show:
                showLauncher(state: state)
            case .toggle:
                toggleLauncher()
            case .triggerHoveredAndClose:
                triggerHoveredSectorAndClose(state: state)
            }
        }
    }

    // MARK: - Permission Watchdog

    private func startWatchdog() {
        stopWatchdog()
        permissionWatchdog = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            if !AXIsProcessTrusted() {
                Task { @MainActor in
                    self.stopWatchdog()
                    self.removeEventMonitors()
                    NotificationCenter.default.post(name: .launcherAccessibilityPermissionLost, object: nil)
                }
            }
        }
    }

    private func stopWatchdog() {
        permissionWatchdog?.invalidate()
        permissionWatchdog = nil
    }
}
