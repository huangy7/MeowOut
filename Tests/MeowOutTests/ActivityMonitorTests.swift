import XCTest
@testable import MeowOut

@MainActor
final class ActivityMonitorTests: XCTestCase {
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
}
