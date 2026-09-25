import XCTest
@testable import MeowOut

@MainActor
final class TrayIconRendererTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: AppState.Keys.enableTrayPetAnimation.rawValue)
    }

    override func tearDown() {
        super.tearDown()
        UserDefaults.standard.removeObject(forKey: AppState.Keys.enableTrayPetAnimation.rawValue)
    }

    func testShouldAnimateRequiresBothWalkingAndToggle() {
        let state = AppState()

        state.isWalking = true
        state.enableTrayPetAnimation = true
        XCTAssertTrue(TrayIconRenderer.shouldAnimate(appState: state))

        // 关掉「猫要不要动」→ 即使正在走也不动
        state.enableTrayPetAnimation = false
        XCTAssertFalse(TrayIconRenderer.shouldAnimate(appState: state))

        // 用户空闲（isWalking 为 false）→ 即使开关打开也不动
        state.enableTrayPetAnimation = true
        state.isWalking = false
        XCTAssertFalse(TrayIconRenderer.shouldAnimate(appState: state))
    }

    func testAnimationToggleDefaultsToOn() {
        // 未写入过偏好时应默认开启动画，保持既有观感
        let state = AppState()
        XCTAssertTrue(state.enableTrayPetAnimation)
    }

    func testAnimationTogglePersists() {
        let state = AppState()
        state.enableTrayPetAnimation = false
        XCTAssertFalse(AppState().enableTrayPetAnimation, "关闭后应持久化到偏好设置")
    }
}
