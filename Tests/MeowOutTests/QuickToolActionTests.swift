import XCTest
@testable import MeowOut

@MainActor
final class QuickToolActionTests: XCTestCase {
    func testKeepAwakeResolvesAsToggleWithInactiveState() {
        let state = AppState()
        state.isKeepingAwake = false

        let descriptor = QuickToolActionResolver.descriptor(
            for: .builtIn(.keepAwake),
            appState: state
        )

        XCTAssertEqual(descriptor.id, "keepAwake")
        XCTAssertEqual(descriptor.behavior, .toggle)
        XCTAssertEqual(descriptor.displayName, I18n.localized("menu_keep_awake", language: state.language))
        XCTAssertEqual(descriptor.iconText, "☕️")
        XCTAssertEqual(descriptor.state?.isActive, false)
        XCTAssertEqual(descriptor.state?.subtitle, I18n.localized("tile_inactive", language: state.language))
    }

    func testKeepAwakeResolvesAsToggleWithActiveState() {
        let state = AppState()
        state.isKeepingAwake = true

        let descriptor = QuickToolActionResolver.descriptor(
            for: .builtIn(.keepAwake),
            appState: state
        )

        XCTAssertEqual(descriptor.behavior, .toggle)
        XCTAssertEqual(descriptor.state?.isActive, true)
        XCTAssertEqual(descriptor.state?.subtitle, I18n.localized("tile_active", language: state.language))
    }

    func testKeepAwakeExecuteTogglesStateAndCanBeCleanedUp() {
        let state = AppState()
        state.isKeepingAwake = false

        let descriptor = QuickToolActionResolver.descriptor(
            for: .builtIn(.keepAwake),
            appState: state
        )

        descriptor.execute()
        XCTAssertEqual(state.isKeepingAwake, true)

        descriptor.execute()
        XCTAssertEqual(state.isKeepingAwake, false)
    }

    func testMemosQuickCaptureResolvesAsLaunchAction() {
        let state = AppState()

        let descriptor = QuickToolActionResolver.descriptor(
            for: .builtIn(.memosQuickCapture),
            appState: state
        )

        XCTAssertEqual(descriptor.behavior, .launch)
        XCTAssertNil(descriptor.state)
        XCTAssertEqual(descriptor.postExecutionBehavior, .closeImmediately)
    }

    func testAppShortcutResolvesAsLaunchAction() {
        let state = AppState()
        let tool = QuickTool.appShortcut(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000123")!,
            name: "Safari",
            path: "/Applications/Safari.app",
            bookmarkData: nil
        )

        let descriptor = QuickToolActionResolver.descriptor(for: tool, appState: state)

        XCTAssertEqual(descriptor.id, "00000000-0000-0000-0000-000000000123")
        XCTAssertEqual(descriptor.behavior, .launch)
        XCTAssertTrue(descriptor.displayName == "Safari" || descriptor.displayName == "Safari浏览器")
        XCTAssertEqual(descriptor.iconText, nil)
        XCTAssertEqual(descriptor.appPath, "/Applications/Safari.app")
        XCTAssertEqual(descriptor.postExecutionBehavior, .closeImmediately)
    }
}
