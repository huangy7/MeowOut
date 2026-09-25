import XCTest
@testable import MeowOut

@MainActor
final class ActivityMonitorTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: AppState.Keys.enableRestReminder.rawValue)
        UserDefaults.standard.removeObject(forKey: AppState.Keys.workDurationMinutes.rawValue)
        UserDefaults.standard.removeObject(forKey: AppState.Keys.alertBeforeRestMinutes.rawValue)
    }

    override func tearDown() {
        super.tearDown()
        UserDefaults.standard.removeObject(forKey: AppState.Keys.enableRestReminder.rawValue)
        UserDefaults.standard.removeObject(forKey: AppState.Keys.workDurationMinutes.rawValue)
        UserDefaults.standard.removeObject(forKey: AppState.Keys.alertBeforeRestMinutes.rawValue)
    }

    func testThresholdTransitions() {
        let state = AppState()
        // Override for fast testing using the new persistent properties
        // workDurationMinutes = 2 (120s), alertBeforeRestMinutes = 1 (alert at 60s)
        state.workDurationMinutes = 2
        state.alertBeforeRestMinutes = 1
        
        let monitor = ActivityMonitor(appState: state)
        
        // Mock 65 seconds of work (should be alerting because 65 > 60)
        monitor.tick(simulatedIdleTime: 0, dt: 65)
        XCTAssertEqual(state.currentState, .alerting)
        
        // Mock idle to trigger rollback (default rollbackThreshold is 120s)
        monitor.tick(simulatedIdleTime: 121, dt: 1)
        XCTAssertEqual(state.currentState, .idle)
        // 65 - 120 = -55, max(0, -55) = 0
        XCTAssertEqual(state.workElapsed, 0)
    }
    
    func testPauseFunctionality() {
        let state = AppState()
        let monitor = ActivityMonitor(appState: state)
        
        state.currentState = .paused
        state.pauseRemaining = 60
        
        // Tick 30 seconds
        monitor.tick(simulatedIdleTime: 0, dt: 30)
        XCTAssertEqual(state.currentState, .paused)
        XCTAssertEqual(state.pauseRemaining, 30)
        
        // Tick another 31 seconds (total 61)
        monitor.tick(simulatedIdleTime: 0, dt: 31)
        XCTAssertEqual(state.currentState, .working)
        XCTAssertEqual(state.workElapsed, 0)
    }

    func testHistorySync() {
        let state = AppState()
        state.workHistory = [:]
        let monitor = ActivityMonitor(appState: state)
        
        // Simulate active work
        monitor.tick(simulatedIdleTime: 0, dt: 10)
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let key = formatter.string(from: Date())
        
        XCTAssertEqual(state.workHistory[key], 10)
        
        // Simulate rollback (idle)
        // Rollback threshold is min(180, (restToResetMinutes / 2.5) * 60)
        // Default restToResetMinutes = 5, so rollbackThreshold = 120s
        state.workElapsed = 500
        // We need to make sure history already has some value to subtract from
        // tick above added 10. Let's add more.
        state.workHistory[key] = 500
        
        monitor.tick(simulatedIdleTime: 121, dt: 0.2) // Triggers rollback
        
        // 500 - 120 = 380 totalWorkToday
        XCTAssertEqual(state.workHistory[key], 500 - 120)
        
        // Cleanup
        UserDefaults.standard.removeObject(forKey: "workHistory")
    }
    
    func testMidnightResetClearsDailyLogs() {
        let appState = AppState()
        appState.dailyLogs = [SessionLog(phase: .working), SessionLog(phase: .resting)]
        
        let monitor = ActivityMonitor(appState: appState)
        
        // Simulate a date change by setting lastStatResetDate to yesterday
        let calendar = Calendar.current
        appState.lastStatResetDate = calendar.date(byAdding: .day, value: -1, to: Date())
        
        monitor.tick(simulatedIdleTime: 0)
        
        // Logs should be cleared, but one new log for the current state should be added
        XCTAssertEqual(appState.dailyLogs.count, 1)
        XCTAssertEqual(appState.dailyLogs.first?.phase, appState.currentState)
    }

    func testWarningDismissal() {
        let state = AppState()
        state.workDurationMinutes = 2
        state.alertBeforeRestMinutes = 1
        
        let monitor = ActivityMonitor(appState: state)
        let escapeHatch = EscapeHatch(appState: state)
        
        // 1. Move to alerting state (65s elapsed, threshold is 60s)
        monitor.tick(simulatedIdleTime: 0, dt: 65)
        XCTAssertEqual(state.currentState, .alerting)
        XCTAssertFalse(state.warningDismissed)
        
        // 2. Drive the warning cat away (trigger escape during alerting)
        escapeHatch.triggerEscape()
        XCTAssertEqual(state.currentState, .working)
        XCTAssertTrue(state.warningDismissed)
        XCTAssertEqual(state.workElapsed, 65) // Work timer should NOT be reset
        
        // 3. Tick again (5s). Should stay in working state because warning is dismissed
        monitor.tick(simulatedIdleTime: 0, dt: 5)
        XCTAssertEqual(state.currentState, .working)
        XCTAssertEqual(state.workElapsed, 70)
        
        // 4. Tick past maxWorkTime (120s). Should transition to resting
        monitor.tick(simulatedIdleTime: 0, dt: 51) // 70 + 51 = 121s (> 120s)
        XCTAssertEqual(state.currentState, .resting)
        
        // 5. Escape rest -> resets workElapsed to 0 -> warningDismissed becomes false
        escapeHatch.triggerEscape()
        XCTAssertEqual(state.currentState, .working)
        XCTAssertEqual(state.workElapsed, 0)
        XCTAssertFalse(state.warningDismissed)
    }
    
    func testOverworkingTransition() {
        let state = AppState()
        state.workDurationMinutes = 2
        state.restDurationMinutes = 1
        
        let monitor = ActivityMonitor(appState: state)
        
        // 1. Tick past maxWorkTime (120s) to transition to resting
        monitor.tick(simulatedIdleTime: 0, dt: 121)
        XCTAssertEqual(state.currentState, .resting)
        XCTAssertEqual(state.restRemaining, 60)
        // Transitions to resting at the end of working tick, so remains true until next tick
        XCTAssertTrue(state.isWalking)
        
        // 1b. Tick once while resting with no activity to set isWalking to false
        monitor.tick(simulatedIdleTime: 30, dt: 0)
        XCTAssertFalse(state.isWalking)
        
        // 2. Next tick with user activity (simulatedIdleTime < 30) -> overworking
        monitor.tick(simulatedIdleTime: 5, dt: 5)
        XCTAssertEqual(state.currentState, .overworking)
        XCTAssertEqual(state.restRemaining, 55)
        XCTAssertTrue(state.isWalking)
        
        // 3. Tick with no user activity (simulatedIdleTime >= 30) -> resting
        monitor.tick(simulatedIdleTime: 35, dt: 5)
        XCTAssertEqual(state.currentState, .resting)
        XCTAssertEqual(state.restRemaining, 50)
        XCTAssertFalse(state.isWalking)
        
        // 4. Tick with user activity again -> overworking
        monitor.tick(simulatedIdleTime: 0, dt: 5)
        XCTAssertEqual(state.currentState, .overworking)
        XCTAssertEqual(state.restRemaining, 45)
        XCTAssertTrue(state.isWalking)
        
        // 5. Tick until restRemaining <= 0 -> back to working
        monitor.tick(simulatedIdleTime: 0, dt: 46)
        XCTAssertEqual(state.currentState, .working)
        XCTAssertEqual(state.workElapsed, 0)
        // Transition back to working happens inside resting block, so isWalking is false on this tick
        XCTAssertFalse(state.isWalking)
    }

    func testDisabledRestReminderDoesNotTriggerAlertOrRest() {
        let state = AppState()
        state.enableRestReminder = false
        state.workDurationMinutes = 2
        state.alertBeforeRestMinutes = 1
        
        let monitor = ActivityMonitor(appState: state)
        
        // Simulate 70s active work (would normally trigger alerting because 70 > 60)
        monitor.tick(simulatedIdleTime: 0, dt: 70)
        XCTAssertEqual(state.currentState, .working, "State must remain .working when rest reminder is disabled")
        
        // Simulate another 60s active work (total 130s, would normally trigger resting because 130 > 120)
        monitor.tick(simulatedIdleTime: 0, dt: 60)
        XCTAssertEqual(state.currentState, .working, "State must remain .working when rest reminder is disabled")
        
        // But workElapsed should still accumulate normally for daily stats
        XCTAssertGreaterThanOrEqual(state.workElapsed, 130)
    }

    func testDynamicDisabledRestReminderConvergesToWorking() {
        let state = AppState()
        let monitor = ActivityMonitor(appState: state)
        
        // 1. Resting -> Working
        state.enableRestReminder = true
        state.currentState = .resting
        state.restRemaining = 60
        state.enableRestReminder = false
        monitor.tick(simulatedIdleTime: 0, dt: 1)
        XCTAssertEqual(state.currentState, .working)
        
        // Also verify convergence via tick directly when resting
        state.currentState = .resting
        state.restRemaining = 60
        monitor.tick(simulatedIdleTime: 0, dt: 1)
        XCTAssertEqual(state.currentState, .working)
        XCTAssertEqual(state.restRemaining, 0)
        
        // 2. Overworking -> Working
        state.enableRestReminder = true
        state.currentState = .overworking
        state.restRemaining = 60
        state.enableRestReminder = false
        monitor.tick(simulatedIdleTime: 0, dt: 1)
        XCTAssertEqual(state.currentState, .working)
        
        // Also verify convergence via tick directly when overworking
        state.currentState = .overworking
        state.restRemaining = 60
        monitor.tick(simulatedIdleTime: 0, dt: 1)
        XCTAssertEqual(state.currentState, .working)
        XCTAssertEqual(state.restRemaining, 0)
        
        // 3. Alerting -> Working
        state.enableRestReminder = true
        state.currentState = .alerting
        state.enableRestReminder = false
        monitor.tick(simulatedIdleTime: 0, dt: 1)
        XCTAssertEqual(state.currentState, .working)
        
        // Also verify convergence via tick directly when alerting
        state.currentState = .alerting
        monitor.tick(simulatedIdleTime: 0, dt: 1)
        XCTAssertEqual(state.currentState, .working)
    }

    // MARK: - 宠物动画与健康作息开关的联动

    func testMasterSwitchOffKeepsPetStillEvenWhenUserIsActive() {
        // 设置项文案承诺「关闭后宠物静默不打扰」：总开关关闭时，
        // 即使用户正在活跃（idle 为 0），宠物也不应走动
        let state = AppState()
        state.enableRestReminder = false
        let monitor = ActivityMonitor(appState: state)

        monitor.tick(simulatedIdleTime: 0, dt: 5)

        XCTAssertFalse(state.isWalking, "健康作息关闭时宠物应保持静默")
    }

    func testActiveUserWalksWhenHealthEnabled() {
        // 对照组：总开关打开且用户活跃时，宠物照常走动
        let state = AppState()
        state.enableRestReminder = true
        let monitor = ActivityMonitor(appState: state)

        monitor.tick(simulatedIdleTime: 0, dt: 5)

        XCTAssertTrue(state.isWalking)
    }

    func testMasterSwitchOffStopsPetFromRestingOrAlertingStates() {
        // 从休息/告警态关闭总开关，也应立刻静默
        let state = AppState()
        state.enableRestReminder = false
        state.currentState = .resting
        let monitor = ActivityMonitor(appState: state)

        monitor.tick(simulatedIdleTime: 0, dt: 1)

        XCTAssertFalse(state.isWalking)
    }

    // MARK: - 开关即时生效

    func testTogglingMasterSwitchOffStopsPetWithoutWaitingForTick() {
        // ActivityMonitor 每 5 秒才重算一次 isWalking，若只在 tick 里响应，
        // 用户点完开关最多要等 5 秒宠物才停下。切开关本身应立即生效。
        let state = AppState()
        state.enableRestReminder = true
        state.isWalking = true

        state.enableRestReminder = false

        XCTAssertFalse(state.isWalking, "关闭总开关后应立即静默，无需等待下一个 tick")
    }

    func testTogglingMasterSwitchOnResumesPetWithoutWaitingForTick() {
        let state = AppState()
        state.enableRestReminder = false
        state.isWalking = false

        state.enableRestReminder = true

        XCTAssertTrue(state.isWalking, "开启总开关后应立即恢复走动，无需等待下一个 tick")
    }
}


