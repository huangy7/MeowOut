import Foundation
import CoreGraphics
import AppKit

@MainActor
final class ActivityMonitor {
    private let appState: AppState
    private var timer: Timer?
    
    private var sleepTime: Date?
    private var lastSaveTime: Date = Date()

    init(appState: AppState) {
        self.appState = appState
        checkDailyReset()
        setupSleepNotifications()
        setupTerminationNotification()
    }
    
    private func setupTerminationNotification() {
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.appState.flushStatsToDisk()
            }
        }
    }
    
    private func checkDailyReset() {
        let now = Date()
        let calendar = Calendar.current
        if let lastReset = appState.lastStatResetDate {
            if !calendar.isDate(now, inSameDayAs: lastReset) {
                appState.lastStatResetDate = now
                appState.dailyLogs.removeAll()
                appState.dailyLogs.append(SessionLog(startTime: now, phase: appState.currentState))
                appState.todayEscapeCount = 0
            }
        } else {
            appState.lastStatResetDate = now
        }
    }
    
    private func setupSleepNotifications() {
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in 
                self?.appState.flushStatsToDisk()
                self?.handleSleep() 
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.handleWake() }
        }
    }
    
    private func handleSleep() {
        sleepTime = Date()
        timer?.invalidate()
        timer = nil
    }
    
    private func handleWake() {
        if let sleepAt = sleepTime {
            let awayDuration = Date().timeIntervalSince(sleepAt)
            if awayDuration >= appState.resetThreshold {
                appState.workElapsed = 0
                appState.currentState = .working
            } else if awayDuration >= appState.rollbackThreshold {
                let rollbackDate = max(
                    appState.dailyLogs.last?.startTime ?? Date(),
                    Date().addingTimeInterval(-appState.rollbackThreshold)
                )
                appState.recordPhaseTransition(from: appState.currentState, to: .idle, at: rollbackDate)
                appState.currentState = .idle
            }
        }
        sleepTime = nil
        start()
    }
    
    deinit {
        appState.flushStatsToDisk()
        timer?.invalidate()
    }
    
    func start() {
        timer?.invalidate()
        // 🔥 CPU 优化：后台监控改为每 5 秒一次
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick(dt: 5.0) }
        }
    }
    
    func tick(simulatedIdleTime: TimeInterval? = nil, dt: TimeInterval = 5.0) {
        checkDailyReset()
        
        guard !appState.isPreviewing else { return }
        
        let idle: TimeInterval
        if let sim = simulatedIdleTime {
            idle = sim
        } else {
            let mouseMoved = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .mouseMoved)
            let leftMouseDown = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .leftMouseDown)
            let rightMouseDown = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .rightMouseDown)
            let scrollWheel = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .scrollWheel)
            let keyDown = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
            idle = min(mouseMoved, leftMouseDown, rightMouseDown, scrollWheel, keyDown)
        }
        
        if appState.currentState == .paused || appState.currentState == .breathing || appState.currentState == .overworking || appState.currentState == .resting {
            if appState.currentState == .paused {
                appState.pauseRemaining -= dt
                if appState.pauseRemaining <= 0 {
                    appState.currentState = .working
                    appState.workElapsed = 0
                    appState.flushStatsToDisk()
                }
            }
            
            // Allow rest to continue if user is breathing/resting/overworking
            if appState.currentState == .breathing || appState.currentState == .resting || appState.currentState == .overworking {
                appState.restRemaining -= dt
                if appState.restRemaining <= 0 {
                    if appState.currentState != .breathing {
                        appState.workElapsed = 0
                        appState.currentState = .working
                        appState.flushStatsToDisk()
                    }
                } else {
                    // Smart transition between Overworking and Resting
                    if idle < 25 && appState.currentState == .resting {
                        appState.changeState(to: .overworking)
                    } else if idle >= 35 && appState.currentState == .overworking {
                        let restingStartDate = max(
                            appState.dailyLogs.last?.startTime ?? Date(),
                            Date().addingTimeInterval(-35)
                        )
                        appState.changeState(to: .resting, at: restingStartDate)
                    }
                }
            }
            
            appState.isWalking = (appState.currentState == .breathing || appState.currentState == .overworking)
            return
        }
        
        if idle >= appState.rollbackThreshold {
            if appState.currentState != .idle && appState.currentState != .resting {
                let rb = appState.rollbackThreshold
                appState.workElapsed = max(0, appState.workElapsed - rb)
                updateHistory(dt: -rb)
                
                let rollbackDate = max(
                    appState.dailyLogs.last?.startTime ?? Date(),
                    Date().addingTimeInterval(-rb)
                )
                appState.recordPhaseTransition(from: appState.currentState, to: .idle, at: rollbackDate)
                
                appState.currentState = .idle
                appState.flushStatsToDisk()
            }
            
            if idle >= appState.resetThreshold {
                appState.workElapsed = 0
            }
            
            appState.isWalking = false
            return
        }
        
        if appState.currentState == .idle {
            appState.currentState = .working
        }
        
        appState.workElapsed += dt
        updateHistory(dt: dt)
        
        // 只要用户在动，标记为行走，具体的动画帧由 View 层的 Timer 驱动
        appState.isWalking = true
        
        if appState.workElapsed >= appState.maxWorkTime {
            appState.currentState = .resting
            appState.restRemaining = appState.defaultRestTime
            appState.flushStatsToDisk()
        } else if appState.workElapsed >= appState.alertThreshold {
            if !appState.warningDismissed {
                appState.currentState = .alerting
            }
        }
        
        if Date().timeIntervalSince(lastSaveTime) >= 3600 {
            appState.flushStatsToDisk()
            lastSaveTime = Date()
        }
    }

    private func updateHistory(dt: TimeInterval) {
        let key = appState.dateKey(for: Date())
        var history = appState.workHistory
        let current = history[key] ?? 0
        history[key] = max(0, current + dt)
        appState.workHistory = history
    }
}
