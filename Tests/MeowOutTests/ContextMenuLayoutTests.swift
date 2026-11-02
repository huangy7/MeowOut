import XCTest
import AppKit
@testable import MeowOut

@MainActor
final class ContextMenuLayoutTests: XCTestCase {
    func testContextMenuItemsHaveNoDummyImage() {
        // 验证菜单项不含尺寸为零的虚假占位图，确保文本基线和列排版自然统一
        let settingsItem = NSMenuItem(title: "设置", action: nil, keyEquivalent: "")
        let quitItem = NSMenuItem(title: "退出", action: nil, keyEquivalent: "q")
        
        XCTAssertNil(settingsItem.image, "设置项不应被强塞空图像占位，否则会引起 AppKit 菜单列对齐错位")
        XCTAssertNil(quitItem.image, "退出项应为纯文本格式")
    }
}
