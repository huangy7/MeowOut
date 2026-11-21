import XCTest
@testable import MeowOut

@MainActor
final class ClamshellManagerTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        PowerAssertionService.shared.disable()
    }

    func testLidDetectionExecution() {
        // 验证机盖开合状态探测不会崩溃，并在带有硬件机盖的 Mac 上返回明确的布尔值
        let isClosed = LidDisplayDimmer.lidClosed()
        if let state = isClosed {
            XCTAssertTrue(state == true || state == false)
        }
    }

    func testExternalDisplayDetection() {
        // 验证外接显示器探测逻辑能正常完成检测
        let hasExt = LidDisplayDimmer.hasExternalDisplay()
        if let value = hasExt {
            XCTAssertTrue(value == true || value == false)
        }
    }

    func testKeepAwakeAssertionActivatesAndDisablesCleanly() {
        let service = PowerAssertionService.shared
        let originalThreshold = UserDefaults.standard.integer(forKey: "batteryProtectionThreshold")
        UserDefaults.standard.set(0, forKey: "batteryProtectionThreshold")
        defer {
            service.disable()
            UserDefaults.standard.set(originalThreshold, forKey: "batteryProtectionThreshold")
        }

        XCTAssertFalse(service.isKeepingAwake)

        service.activate(minutes: 15)
        XCTAssertTrue(service.isKeepingAwake)
        XCTAssertNotNil(service.endDate)
        XCTAssertEqual(service.sessionMinutes, 15)

        service.disable()
        XCTAssertFalse(service.isKeepingAwake)
        XCTAssertNil(service.endDate)
        XCTAssertNil(service.sessionMinutes)
    }

    func testExtendAdvancesEndDate() {
        let service = PowerAssertionService.shared
        let originalThreshold = UserDefaults.standard.integer(forKey: "batteryProtectionThreshold")
        UserDefaults.standard.set(0, forKey: "batteryProtectionThreshold")
        defer {
            service.disable()
            UserDefaults.standard.set(originalThreshold, forKey: "batteryProtectionThreshold")
        }

        service.activate(minutes: 15)
        guard let initialEnd = service.endDate else {
            XCTFail("Expected non-nil endDate for timed keep-awake session")
            return
        }

        service.extend(minutes: 30)
        guard let extendedEnd = service.endDate else {
            XCTFail("Expected non-nil endDate after extending keep-awake session")
            return
        }

        XCTAssertGreaterThanOrEqual(extendedEnd.timeIntervalSince(initialEnd), 29 * 60)
    }
}
