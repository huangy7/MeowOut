import AppKit
import XCTest
@testable import MeowOut

@MainActor
final class QuickMemoWindowControllerTests: XCTestCase {
    func testWindowUsesNativeVisibleTitle() {
        let controller = QuickMemoWindowController.shared

        XCTAssertEqual(controller.window?.titleVisibility, .visible)
    }

    func testTitleUpdateNotificationUpdatesWindowTitle() {
        let controller = QuickMemoWindowController.shared

        NotificationCenter.default.post(
            name: .quickMemoTitleDidChange,
            object: nil,
            userInfo: ["title": "测试标题"]
        )

        XCTAssertEqual(controller.window?.title, "测试标题")
    }
}
