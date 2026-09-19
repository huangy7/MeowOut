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

    func testEmptyQuickToolsRestoredCorrectly() {
        let state = AppState()
        // Clear all quick tools
        state.quickTools = []
        
        // Create a new state instance to trigger loadQuickTools() from UserDefaults
        let newState = AppState()
        
        // The new state should load the empty array from UserDefaults, not default tools
        XCTAssertTrue(newState.quickTools.isEmpty, "Empty quick tools should be restored correctly")
    }

    func testScreenCleaningState() {
        let state = AppState()
        XCTAssertFalse(state.isScreenCleaningActive)
        
        state.isScreenCleaningActive = true
        XCTAssertTrue(state.isScreenCleaningActive)
    }

    @MainActor
    func testLauncherTriggerModeDefaultsToKeyboardShortcut() {
        UserDefaults.standard.removeObject(forKey: "launcherTriggerMode")
        let state = AppState()
        XCTAssertEqual(state.launcherTriggerMode, .keyboardShortcut)
    }

    @MainActor
    func testLauncherTriggerModePersists() {
        UserDefaults.standard.removeObject(forKey: "launcherTriggerMode")
        let state = AppState()

        state.launcherEnabled = false
        state.launcherTriggerMode = .advancedModifier

        let restored = AppState()
        XCTAssertEqual(restored.launcherTriggerMode, .advancedModifier)

        LauncherTriggerService.shared.stop()
        UserDefaults.standard.removeObject(forKey: "launcherEnabled")
        UserDefaults.standard.removeObject(forKey: "launcherTriggerMode")
    }

    func testTrayCardsCustomizationSettingsPersistence() {
        UserDefaults.standard.removeObject(forKey: AppState.Keys.enableRestReminder.rawValue)
        UserDefaults.standard.removeObject(forKey: AppState.Keys.showQuickToolsCard.rawValue)
        defer {
            UserDefaults.standard.removeObject(forKey: AppState.Keys.enableRestReminder.rawValue)
            UserDefaults.standard.removeObject(forKey: AppState.Keys.showQuickToolsCard.rawValue)
        }

        let state = AppState()
        
        // Default values should be true
        XCTAssertTrue(state.enableRestReminder)
        XCTAssertTrue(state.showQuickToolsCard)
        
        // Set to false and verify persistence
        state.enableRestReminder = false
        XCTAssertFalse(state.enableRestReminder)
        
        state.showQuickToolsCard = false
        XCTAssertFalse(state.showQuickToolsCard)
        
        // Test across instances
        let state2 = AppState()
        XCTAssertFalse(state2.enableRestReminder)
        XCTAssertFalse(state2.showQuickToolsCard)

        // Test state2.resetToDefaults() restores them to true
        state2.resetToDefaults()
        XCTAssertTrue(state2.enableRestReminder)
        XCTAssertTrue(state2.showQuickToolsCard)

        // Also test resetAllSettings() restores them to true
        state2.enableRestReminder = false
        state2.showQuickToolsCard = false
        state2.resetAllSettings()
        XCTAssertTrue(state2.enableRestReminder)
        XCTAssertTrue(state2.showQuickToolsCard)

        // Test resetIntervalsToDefaults() restores enableRestReminder to true
        state2.enableRestReminder = false
        state2.resetIntervalsToDefaults()
        XCTAssertTrue(state2.enableRestReminder)

        UserDefaults.standard.removeObject(forKey: AppState.Keys.enableRestReminder.rawValue)
        UserDefaults.standard.removeObject(forKey: AppState.Keys.showQuickToolsCard.rawValue)
    }
    
    func testEnableRestReminderAutoConvergence() {
        UserDefaults.standard.removeObject(forKey: AppState.Keys.enableRestReminder.rawValue)
        defer {
            UserDefaults.standard.removeObject(forKey: AppState.Keys.enableRestReminder.rawValue)
        }

        let state = AppState()
        
        // 1. Test .alerting -> .working
        state.enableRestReminder = true
        state.currentState = .alerting
        state.enableRestReminder = false
        XCTAssertEqual(state.currentState, .working)
        
        // 2. Test .resting -> .working
        state.enableRestReminder = true
        state.currentState = .resting
        state.enableRestReminder = false
        XCTAssertEqual(state.currentState, .working)

        // 3. Test .overworking -> .working
        state.enableRestReminder = true
        state.currentState = .overworking
        state.enableRestReminder = false
        XCTAssertEqual(state.currentState, .working)

        UserDefaults.standard.removeObject(forKey: AppState.Keys.enableRestReminder.rawValue)
    }
}

