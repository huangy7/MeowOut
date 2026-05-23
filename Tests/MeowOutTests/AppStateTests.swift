// Tests/MeowOutTests/AppStateTests.swift
import XCTest
@testable import MeowOut

final class AppStateTests: XCTestCase {
    func testStateTransitions() {
        let state = AppState()
        XCTAssertEqual(state.currentState, .working)
        state.currentState = .alerting
        XCTAssertEqual(state.currentState, .alerting)
        
        state.currentState = .paused
        XCTAssertEqual(state.currentState, .paused)
    }
    
    func testNewProperties() {
        let state = AppState()
        XCTAssertFalse(state.isPaused)
        XCTAssertEqual(state.restRemaining, 0)
        
        state.isPaused = true
        state.restRemaining = 300
        
        XCTAssertTrue(state.isPaused)
        XCTAssertEqual(state.restRemaining, 300)
    }

    func testPersistence() {
        // Reset UserDefaults for a clean test
        let key = "workDurationMinutes"
        UserDefaults.standard.removeObject(forKey: key)
        
        let state = AppState()
        state.workDurationMinutes = 30
        XCTAssertEqual(UserDefaults.standard.integer(forKey: key), 30)
        
        let newState = AppState()
        XCTAssertEqual(newState.workDurationMinutes, 30)
        
        // Cleanup
        UserDefaults.standard.removeObject(forKey: key)
    }

    func testHistoryAndPersonalityProperties() {
        // Clear UserDefaults for isolation
        UserDefaults.standard.removeObject(forKey: "dailyWorkGoal")
        UserDefaults.standard.removeObject(forKey: "selectedPersonality")
        UserDefaults.standard.removeObject(forKey: "workHistory")
        
        let state = AppState()
        
        // Default values
        XCTAssertEqual(state.dailyWorkGoal, 8)
        XCTAssertEqual(state.selectedPersonality, .strict)
        XCTAssertTrue(state.workHistory.isEmpty)
        
        // Persistence
        state.dailyWorkGoal = 10
        state.selectedPersonality = .gentle
        state.workHistory = ["2026-05-16": 3600]
        state.flushStatsToDisk()
        
        let newState = AppState()
        XCTAssertEqual(newState.dailyWorkGoal, 10)
        XCTAssertEqual(newState.selectedPersonality, .gentle)
        XCTAssertEqual(newState.workHistory["2026-05-16"], 3600)
        
        // Cleanup
        UserDefaults.standard.removeObject(forKey: "dailyWorkGoal")
        UserDefaults.standard.removeObject(forKey: "selectedPersonality")
        UserDefaults.standard.removeObject(forKey: "workHistory")
    }

    func testDailyLogsTracking() {
        let appState = AppState()
        XCTAssertEqual(appState.dailyLogs.count, 1, "dailyLogs should have an initial log")
        XCTAssertEqual(appState.dailyLogs.first?.phase, .working)
        
        // Changing state should start a new log
        // Use a date > 60s in the future to avoid "Smart merge" logic in AppState.changeState
        let futureDate = Date().addingTimeInterval(70)
        appState.changeState(to: .resting, at: futureDate)
        
        XCTAssertEqual(appState.dailyLogs.count, 2)
        XCTAssertNotNil(appState.dailyLogs.first?.endTime)
        XCTAssertEqual(appState.dailyLogs.first?.phase, .working)
        
        XCTAssertEqual(appState.dailyLogs.last?.phase, .resting)
        XCTAssertNil(appState.dailyLogs.last?.endTime)
    }

    func testQuickToolsInitialStateAndToggle() {
        let state = AppState()
        XCTAssertFalse(state.isKeepingAwake)
        XCTAssertFalse(state.isKeyboardCleaningActive)
        
        state.isKeepingAwake = true
        XCTAssertTrue(state.isKeepingAwake)
        
        state.isKeyboardCleaningActive = true
        XCTAssertTrue(state.isKeyboardCleaningActive)
    }
}
