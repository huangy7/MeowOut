import XCTest
@testable import MeowOut

final class RefreshIconButtonRotationTests: XCTestCase {
    func testTapRotatesOneFullTurn() {
        XCTAssertEqual(RefreshIconButtonRotation.tapIncrement, 360)
    }

    func testNormalizedRotationKeepsVisibleAngleBounded() {
        XCTAssertEqual(RefreshIconButtonRotation.normalized(725), 5)
        XCTAssertEqual(RefreshIconButtonRotation.normalized(360), 0)
    }
}
