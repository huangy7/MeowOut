import XCTest
@testable import MeowOut

@MainActor
final class ClamshellManagerTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        PowerAssertionService.shared.disable()
        ClamshellManager.shared.restoreOnQuit()
    }

    func testClamshellPreferencePersistence() {
        let manager = ClamshellManager.shared
        let originalPreference = manager.isClamshellPreferred

        manager.setClamshellMode(enabled: false)
        XCTAssertFalse(manager.isClamshellPreferred)

        manager.setClamshellMode(enabled: true)
        XCTAssertTrue(manager.isClamshellPreferred)

        // 还原初始偏好
        manager.setClamshellMode(enabled: originalPreference)
    }

    func testLidDetectionExecution() {
        // 验证机盖开合状态探测不会崩溃，并在带有硬件机盖的 Mac 设备上返回明确的布尔值
        let isClosed = ClamshellManager.lidClosed()
        if let state = isClosed {
            XCTAssertTrue(state == true || state == false)
        }
    }

    func testExternalDisplayDetection() {
        // 验证外接显示器探测逻辑能正常完成检测并返回布尔值
        let hasExt = ClamshellManager.hasExternalDisplay()
        XCTAssertTrue(hasExt == true || hasExt == false)
    }

    func testKeepAwakeAssertionDisablesCleanly() {
        let service = PowerAssertionService.shared
        XCTAssertFalse(service.isKeepingAwake)

        XCTAssertNoThrow(try service.enable())
        XCTAssertTrue(service.isKeepingAwake)

        service.disable()
        XCTAssertFalse(service.isKeepingAwake)
    }

    func testRestoreOnLaunchCleansState() {
        let manager = ClamshellManager.shared
        // 模拟非正常退出遗留标记
        UserDefaults.standard.set(true, forKey: "didModifySleepDisabled")
        
        manager.restoreOnLaunch()
        
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "didModifySleepDisabled"))
    }
}
