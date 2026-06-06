import XCTest
@testable import MeowOut

final class BreathingVisualMetricsTests: XCTestCase {
    func testBreathingWindowUsesCompactDefaultSize() {
        XCTAssertEqual(BreathingVisualMetrics.windowWidth, 320)
        XCTAssertEqual(BreathingVisualMetrics.windowHeight, 420)
    }

    func testBreathingAnimationFitsCompactWindow() {
        XCTAssertEqual(BreathingVisualMetrics.animationFrameSize, 240)
        XCTAssertEqual(BreathingVisualMetrics.breathingCircleSize, 164)
        XCTAssertLessThan(BreathingVisualMetrics.animationFrameSize, BreathingVisualMetrics.windowWidth)
    }

    func testBreathingControlsKeepComfortablePadding() {
        XCTAssertEqual(BreathingVisualMetrics.horizontalPadding, 22)
        XCTAssertEqual(BreathingVisualMetrics.bottomPadding, 28)
    }
}
