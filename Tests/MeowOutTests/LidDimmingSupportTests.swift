import XCTest
@testable import MeowOut

final class LidDimmingSupportTests: XCTestCase {
    func testLidClosedDimsAndSavesPositiveBrightness() {
        XCTAssertEqual(LidDimmingSupport.lidClosed(currentBrightness: 0.75), .dim(save: 0.75))
    }

    func testLidClosedDoesNothingWhenBrightnessIsZeroOrNil() {
        XCTAssertEqual(LidDimmingSupport.lidClosed(currentBrightness: 0.0), .none)
        XCTAssertEqual(LidDimmingSupport.lidClosed(currentBrightness: -0.1), .none)
        XCTAssertEqual(LidDimmingSupport.lidClosed(currentBrightness: nil), .none)
    }

    func testRestoringReturnsSavedBrightnessOrNone() {
        XCTAssertEqual(LidDimmingSupport.restoring(saved: 0.6), .restore(0.6))
        XCTAssertEqual(LidDimmingSupport.restoring(saved: nil), .none)
    }
}
