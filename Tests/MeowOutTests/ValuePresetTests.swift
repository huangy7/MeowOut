import XCTest
@testable import MeowOut

final class ValuePresetTests: XCTestCase {
    func testSnappedClampsBelowRange() {
        XCTAssertEqual(ValuePreset.workDuration.snapped(3), 15)
    }

    func testSnappedClampsAboveRange() {
        XCTAssertEqual(ValuePreset.workDuration.snapped(500), 120)
    }

    func testSnappedAlignsDownToStep() {
        XCTAssertEqual(ValuePreset.workDuration.snapped(47), 45)
    }

    func testSnappedExactPresetUnchanged() {
        XCTAssertEqual(ValuePreset.workDuration.snapped(45), 45)
    }

    func testSnappedBatteryZeroAllowed() {
        XCTAssertEqual(ValuePreset.batteryThreshold.snapped(0), 0)
    }

    func testIsPreset() {
        XCTAssertTrue(ValuePreset.restDuration.isPreset(5))
        XCTAssertFalse(ValuePreset.restDuration.isPreset(7))
    }

    func testMenuValuesOnlyPresetsWhenCurrentIsPreset() {
        XCTAssertEqual(ValuePreset.workDuration.menuValues(currentValue: 45), [15, 25, 30, 45, 60, 90, 120])
    }

    func testMenuValuesInsertsCustomValueSorted() {
        XCTAssertEqual(ValuePreset.workDuration.menuValues(currentValue: 50), [15, 25, 30, 45, 50, 60, 90, 120])
    }

    func testMenuValuesSnapsMisalignedCurrentValue() {
        XCTAssertEqual(ValuePreset.workDuration.menuValues(currentValue: 47), [15, 25, 30, 45, 60, 90, 120])
    }
}
