import XCTest
@testable import MeowOut

@MainActor
final class WaterReminderControllerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: AppState.Keys.enableRestReminder.rawValue)
        UserDefaults.standard.removeObject(forKey: AppState.Keys.waterReminderEnabled.rawValue)
        UserDefaults.standard.removeObject(forKey: AppState.Keys.waterCustomInterval.rawValue)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: AppState.Keys.enableRestReminder.rawValue)
        UserDefaults.standard.removeObject(forKey: AppState.Keys.waterReminderEnabled.rawValue)
        UserDefaults.standard.removeObject(forKey: AppState.Keys.waterCustomInterval.rawValue)
        super.tearDown()
    }

    func testDisabledRestReminderBlocksWaterReminderTick() {
        let appState = AppState()
        let petState = PetState()
        appState.waterReminderEnabled = true
        appState.waterReminderMode = .custom
        appState.waterCustomInterval = 0 // 0 min ensures immediate trigger if not blocked
        appState.currentState = .working

        let controller = WaterReminderController(appState: appState, petState: petState)
        controller.resetTimer()

        // 1. When enableRestReminder = false, it must be blocked by guard
        appState.enableRestReminder = false
        controller.tick()
        XCTAssertFalse(petState.showWaterButton)
        XCTAssertFalse(petState.bubbleVisible)

        // 2. Contrast check: When enableRestReminder = true, tick immediately triggers
        appState.enableRestReminder = true
        controller.tick()
        XCTAssertTrue(petState.showWaterButton)
        XCTAssertTrue(petState.bubbleVisible)
    }

    func testShowBubbleBlockedWhenRestReminderDisabled() {
        let appState = AppState()
        let petState = PetState()
        appState.enableRestReminder = false

        let controller = WaterReminderController(appState: appState, petState: petState)
        controller.showBubble()

        XCTAssertFalse(petState.showWaterButton)
        XCTAssertFalse(petState.bubbleVisible)
    }

    func testDismissBubbleClearsPetWaterUI() {
        let appState = AppState()
        let petState = PetState()
        let controller = WaterReminderController(appState: appState, petState: petState)

        controller.showBubble()
        XCTAssertTrue(petState.showWaterButton)
        XCTAssertTrue(petState.bubbleVisible)

        controller.dismissBubble()
        XCTAssertFalse(petState.showWaterButton)
        XCTAssertFalse(petState.bubbleVisible)
    }

    func testDismissBubbleDoesNotClearNonWaterBubble() {
        let appState = AppState()
        let petState = PetState()
        petState.bubbleVisible = true
        petState.showWaterButton = false // not a water bubble

        let controller = WaterReminderController(appState: appState, petState: petState)
        controller.dismissBubble()

        // bubbleVisible must stay true
        XCTAssertTrue(petState.bubbleVisible)
    }
}
