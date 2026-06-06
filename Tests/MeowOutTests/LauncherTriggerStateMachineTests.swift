import XCTest
@testable import MeowOut

final class LauncherTriggerStateMachineTests: XCTestCase {
    func testDoubleClickModeDoesNotOpenOnSingleLongPress() {
        var machine = LauncherTriggerStateMachine()
        let config = LauncherTriggerStateMachine.Configuration(
            doubleClickToActivate: true,
            clickToLaunch: true,
            longPressDelay: 0.35,
            doubleClickInterval: 0.30
        )

        XCTAssertEqual(machine.keyDown(at: 10.0, config: config), [])
        XCTAssertEqual(machine.longPressTimerFired(at: 10.34, config: config), [])
        XCTAssertEqual(machine.longPressTimerFired(at: 10.35, config: config), [])
    }

    func testDoubleClickModeDoesNotToggleOnSingleQuickPress() {
        var machine = LauncherTriggerStateMachine()
        let config = LauncherTriggerStateMachine.Configuration(
            doubleClickToActivate: true,
            clickToLaunch: true,
            longPressDelay: 0.35,
            doubleClickInterval: 0.30
        )

        XCTAssertEqual(machine.keyDown(at: 20.0, config: config), [])
        XCTAssertEqual(machine.keyUp(at: 20.08, config: config), [])
    }

    func testDoubleClickModeDoesNotOpenOnQuickSecondPressWithinDoubleClickInterval() {
        var machine = LauncherTriggerStateMachine()
        let config = LauncherTriggerStateMachine.Configuration(
            doubleClickToActivate: true,
            clickToLaunch: true,
            longPressDelay: 0.35,
            doubleClickInterval: 0.30
        )

        XCTAssertEqual(machine.keyDown(at: 30.0, config: config), [])
        XCTAssertEqual(machine.keyUp(at: 30.05, config: config), [])
        XCTAssertEqual(machine.keyDown(at: 30.20, config: config), [])
        XCTAssertEqual(machine.keyUp(at: 30.25, config: config), [])
    }

    func testDoubleClickModeRequiresHoldingSecondPressForConfiguredDuration() {
        var machine = LauncherTriggerStateMachine()
        let config = LauncherTriggerStateMachine.Configuration(
            doubleClickToActivate: true,
            clickToLaunch: true,
            longPressDelay: 2.00,
            doubleClickInterval: 0.30
        )

        XCTAssertEqual(machine.keyDown(at: 60.0, config: config), [])
        XCTAssertEqual(machine.keyUp(at: 60.05, config: config), [])
        XCTAssertEqual(machine.keyDown(at: 60.20, config: config), [])
        XCTAssertEqual(machine.longPressTimerFired(at: 62.19, config: config), [])
        XCTAssertEqual(machine.longPressTimerFired(at: 62.20, config: config), [.show])
    }

    func testReleaseAfterHoldTriggersHoveredSectorOnlyWhenClickToLaunchIsDisabled() {
        var machine = LauncherTriggerStateMachine()
        let config = LauncherTriggerStateMachine.Configuration(
            doubleClickToActivate: false,
            clickToLaunch: false,
            longPressDelay: 0.20,
            doubleClickInterval: 0.30
        )

        XCTAssertEqual(machine.keyDown(at: 40.0, config: config), [])
        XCTAssertEqual(machine.longPressTimerFired(at: 40.20, config: config), [.show])
        XCTAssertEqual(machine.keyUp(at: 40.35, config: config), [.triggerHoveredAndClose])
    }

    func testReleaseAfterHoldKeepsLauncherOpenWhenClickToLaunchIsEnabled() {
        var machine = LauncherTriggerStateMachine()
        let config = LauncherTriggerStateMachine.Configuration(
            doubleClickToActivate: false,
            clickToLaunch: true,
            longPressDelay: 0.20,
            doubleClickInterval: 0.30
        )

        XCTAssertEqual(machine.keyDown(at: 50.0, config: config), [])
        XCTAssertEqual(machine.longPressTimerFired(at: 50.20, config: config), [.show])
        XCTAssertEqual(machine.keyUp(at: 50.35, config: config), [])
    }
}
