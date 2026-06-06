import XCTest
@testable import MeowOut

final class LauncherVisualMetricsTests: XCTestCase {
    func testHoverIconMetricsProvideVisiblePreselection() {
        XCTAssertGreaterThan(LauncherVisualMetrics.hoveredIconScale, LauncherVisualMetrics.normalIconScale)
        XCTAssertLessThan(LauncherVisualMetrics.hoveredIconYOffset, LauncherVisualMetrics.normalIconYOffset)
        XCTAssertEqual(LauncherVisualMetrics.feedbackDelayNanoseconds, 600_000_000)
    }

    func testLauncherWindowLeavesShadowPaddingAroundRing() {
        XCTAssertGreaterThan(LauncherVisualMetrics.windowSize, LauncherVisualMetrics.ringSize)
        XCTAssertGreaterThanOrEqual(
            (LauncherVisualMetrics.windowSize - LauncherVisualMetrics.ringSize) / 2,
            LauncherVisualMetrics.shadowPadding
        )
    }

    func testOuterRingStrokeStaysSubtleOnLightBackgrounds() {
        XCTAssertLessThanOrEqual(LauncherVisualMetrics.outerRingStrokeOpacity, 0.04)
    }

    func testLauncherPanelDoesNotAddSystemShadowOutline() {
        XCTAssertFalse(LauncherVisualMetrics.usesSystemPanelShadow)
    }

    func testMouseTrackingAcceptsFirstClick() {
        XCTAssertTrue(LauncherMouseTrackingPolicy.acceptsFirstMouseClick)
    }

    func testSelectionUsesMouseAngleInsteadOfDefaultSector() {
        let size = CGSize(width: LauncherVisualMetrics.ringSize, height: LauncherVisualMetrics.ringSize)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)

        XCTAssertEqual(
            LauncherSelectionGeometry.sectorIndex(
                at: CGPoint(x: center.x, y: center.y - 90),
                in: size,
                count: 4
            ),
            0
        )
        XCTAssertEqual(
            LauncherSelectionGeometry.sectorIndex(
                at: CGPoint(x: center.x + 90, y: center.y),
                in: size,
                count: 4
            ),
            1
        )
        XCTAssertEqual(
            LauncherSelectionGeometry.sectorIndex(
                at: CGPoint(x: center.x, y: center.y + 90),
                in: size,
                count: 4
            ),
            2
        )
        XCTAssertEqual(
            LauncherSelectionGeometry.sectorIndex(
                at: CGPoint(x: center.x - 90, y: center.y),
                in: size,
                count: 4
            ),
            3
        )
    }

    func testSelectionIgnoresCenterHoleAndOutsideRing() {
        let size = CGSize(width: LauncherVisualMetrics.ringSize, height: LauncherVisualMetrics.ringSize)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)

        XCTAssertNil(LauncherSelectionGeometry.sectorIndex(at: center, in: size, count: 4))
        XCTAssertNil(
            LauncherSelectionGeometry.sectorIndex(
                at: CGPoint(x: center.x + 140, y: center.y),
                in: size,
                count: 4
            )
        )
    }

    func testWindowSelectionMapsMousePointIntoCenteredRing() {
        let windowSize = CGSize(width: LauncherVisualMetrics.windowSize, height: LauncherVisualMetrics.windowSize)
        let ringOrigin = (LauncherVisualMetrics.windowSize - LauncherVisualMetrics.ringSize) / 2
        let ringCenter = ringOrigin + LauncherVisualMetrics.ringSize / 2

        XCTAssertEqual(
            LauncherWindowSelectionGeometry.sectorIndex(
                atWindowPoint: CGPoint(x: ringCenter, y: ringOrigin + 20),
                in: windowSize,
                count: 4
            ),
            0
        )
        XCTAssertEqual(
            LauncherWindowSelectionGeometry.sectorIndex(
                atWindowPoint: CGPoint(x: ringCenter + 90, y: ringCenter),
                in: windowSize,
                count: 4
            ),
            1
        )
        XCTAssertNil(
            LauncherWindowSelectionGeometry.sectorIndex(
                atWindowPoint: CGPoint(x: ringCenter, y: ringCenter),
                in: windowSize,
                count: 4
            )
        )
    }
}
