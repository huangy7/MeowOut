import XCTest
import SwiftUI
@testable import MeowOut

final class LauncherVisualMetricsTests: XCTestCase {
    func testHoverIconMetricsProvideVisiblePreselection() {
        XCTAssertGreaterThan(LauncherVisualMetrics.hoveredIconScale, LauncherVisualMetrics.normalIconScale)
        XCTAssertEqual(LauncherVisualMetrics.hoveredIconScale, 1.04, accuracy: 0.001)
        XCTAssertEqual(LauncherVisualMetrics.hoveredIconYOffset, 0)
        XCTAssertEqual(LauncherVisualMetrics.feedbackDelayNanoseconds, 600_000_000)
    }

    func testLauncherWindowLeavesShadowPaddingAroundRing() {
        XCTAssertEqual(LauncherVisualMetrics.windowSize, 300)
        XCTAssertEqual(LauncherVisualMetrics.ringSize, 260)
        XCTAssertGreaterThanOrEqual(
            (LauncherVisualMetrics.windowSize - LauncherVisualMetrics.ringSize) / 2,
            LauncherVisualMetrics.shadowPadding
        )
    }

    func testDonutInnerRadiusRatioAccommodatesCenterHole() {
        // 甜甜圈孔径约 100pt，外径 260pt，比例约 0.385
        XCTAssertEqual(LauncherVisualMetrics.innerRadiusRatio, 0.385, accuracy: 0.01)
    }

    func testDonutRingShapeProducesHollowGeometry() {
        let shape = DonutRingShape()
        XCTAssertEqual(shape.innerRadiusRatio, LauncherVisualMetrics.innerRadiusRatio)
        
        let rect = CGRect(x: 0, y: 0, width: 260, height: 260)
        let path = shape.path(in: rect)
        
        let center = CGPoint(x: 130, y: 130)
        // 中心孔内（非零绕数正反双圆挖空后，中心点及内孔不包含在 path 内部）
        XCTAssertFalse(path.contains(center))
        XCTAssertFalse(path.contains(CGPoint(x: 130, y: 100)))
        
        // 环体有效区域包含在 path 内部（距中心 88pt）
        XCTAssertTrue(path.contains(CGPoint(x: 130, y: 42)))
        
        // 外圆外部不包含在 path 内部
        XCTAssertFalse(path.contains(CGPoint(x: 130, y: -10)))
    }

    func testDonutRingDualHighlightStrokeOpacities() {
        XCTAssertEqual(LauncherVisualMetrics.outerRingStrokeOpacity, 0.30)
        XCTAssertEqual(LauncherVisualMetrics.innerRingStrokeOpacity, 0.20)
    }

    func testHoveredSectorFillOpacities() {
        XCTAssertEqual(LauncherVisualMetrics.hoveredSectorFillOpacityDark, 0.16)
        XCTAssertEqual(LauncherVisualMetrics.hoveredSectorFillOpacityLight, 0.22)
    }

    func testRingSectorAlignsWithLauncherVisualMetricsInnerRadiusRatio() {
        let sector = RingSector(startAngle: .degrees(0), endAngle: .degrees(90))
        XCTAssertEqual(sector.innerRadiusRatio, LauncherVisualMetrics.innerRadiusRatio)
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
                at: CGPoint(x: center.x, y: center.y - 88),
                in: size,
                count: 4
            ),
            0
        )
        XCTAssertEqual(
            LauncherSelectionGeometry.sectorIndex(
                at: CGPoint(x: center.x + 88, y: center.y),
                in: size,
                count: 4
            ),
            1
        )
        XCTAssertEqual(
            LauncherSelectionGeometry.sectorIndex(
                at: CGPoint(x: center.x, y: center.y + 88),
                in: size,
                count: 4
            ),
            2
        )
        XCTAssertEqual(
            LauncherSelectionGeometry.sectorIndex(
                at: CGPoint(x: center.x - 88, y: center.y),
                in: size,
                count: 4
            ),
            3
        )
    }

    func testSelectionIgnoresCenterHoleAndOutsideRing() {
        let size = CGSize(width: LauncherVisualMetrics.ringSize, height: LauncherVisualMetrics.ringSize)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)

        // 中心孔内（距中心 40pt，小于 innerRadius 50pt）不应命中任何扇区
        XCTAssertNil(LauncherSelectionGeometry.sectorIndex(at: CGPoint(x: center.x, y: center.y - 40), in: size, count: 4))
        XCTAssertNil(LauncherSelectionGeometry.sectorIndex(at: center, in: size, count: 4))
        // 环体有效区域（距中心 88pt）命中
        XCTAssertEqual(LauncherSelectionGeometry.sectorIndex(at: CGPoint(x: center.x, y: center.y - 88), in: size, count: 4), 0)
        // 外圈外侧（距中心 140pt，大于 outerRadius 130pt）不应命中
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

    func testScrollToSwitchLocalizationResolvesAppropriately() {
        XCTAssertEqual(I18n.localized("scroll_to_switch", languageCode: "zh-Hans"), "滚轮切换")
        XCTAssertEqual(I18n.localized("scroll_to_switch", languageCode: "en"), "Scroll to switch")
    }

    func testBottomCapsuleMetricsFitWithinLauncherWindowBounds() {
        let halfWindow = LauncherVisualMetrics.windowSize / 2
        let halfRing = LauncherVisualMetrics.ringSize / 2
        let capsuleOffsetY = halfRing + 6
        let estimatedCapsuleHalfHeight: CGFloat = 11
        
        // 确保胶囊底部在窗口下边缘之内
        XCTAssertLessThan(capsuleOffsetY + estimatedCapsuleHalfHeight, halfWindow)
    }

    @MainActor
    func testBuiltInToolsResolveDescriptorWithBuiltInType() {
        let appState = AppState()
        for type in BuiltInToolType.allCases {
            let descriptor = QuickToolActionResolver.descriptor(for: .builtIn(type), appState: appState)
            XCTAssertEqual(descriptor.builtInType, type, "内置工具 \(type.rawValue) 未正确解析出 builtInType")
            XCTAssertNil(descriptor.appPath, "内置工具 \(type.rawValue) 的 appPath 应为 nil")
        }
    }

    func testSevenNodeRadialMenuMathematicalSymmetry() {
        let count = 7
        let step = 360.0 / Double(count)
        XCTAssertEqual(step, 51.42857, accuracy: 0.001)

        let radius = LauncherVisualMetrics.iconRadius
        for i in 0..<count {
            let angle = Angle.degrees(-90.0 + Double(i) * step)
            let x = radius * cos(CGFloat(angle.radians))
            let y = radius * sin(CGFloat(angle.radians))
            let dist = sqrt(x * x + y * y)
            XCTAssertEqual(dist, radius, accuracy: 0.0001)
        }
    }

    func testAllBuiltInToolIconsLoadSuccessfully() {
        for type in BuiltInToolType.allCases {
            let image = BuiltInToolIconView.loadAssetImage(for: type)
            XCTAssertNotNil(image, "内置图标资源缺失: \(type.rawValue)")
        }
    }

    func testIconSizeMatchesCompactThirtyTwoPoints() {
        XCTAssertEqual(LauncherVisualMetrics.iconSize, 32)
        XCTAssertEqual(LauncherVisualMetrics.iconRadius, 90)
    }

    func testBreathingMarginAroundNodeOnTrack() {
        let outerRadius = LauncherVisualMetrics.ringSize / 2 // 130
        let innerRadius = outerRadius * LauncherVisualMetrics.innerRadiusRatio // 50.7
        let trackRadius = LauncherVisualMetrics.iconRadius // 90
        let nodeHalfHeight: CGFloat = 24 // 节点总高度 48pt 的一半

        let outerMargin = outerRadius - (trackRadius + nodeHalfHeight)
        let innerMargin = (trackRadius - nodeHalfHeight) - innerRadius

        XCTAssertGreaterThanOrEqual(outerMargin, 15.0)
        XCTAssertGreaterThanOrEqual(innerMargin, 15.0)
    }
}

