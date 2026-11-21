import XCTest
import AppKit
@testable import MeowOut

@MainActor
final class ContextMenuLayoutTests: XCTestCase {
    func testContextMenuItemsHaveNoAutoInjectedOrDummyImage() {
        _ = NSApplication.shared

        for (language, expectedSettingsTitle, expectedQuitTitle) in [
            (AppState.AppLanguage.zhHans, "设置", "退出"),
            (AppState.AppLanguage.en, "Settings", "Quit")
        ] {
            let menu = MenuBarController.shared.makeContextMenu(language: language)
            menu.update()

            XCTAssertEqual(menu.items.count, 3)
            let settingsItem = menu.items[0]
            let separatorItem = menu.items[1]
            let quitItem = menu.items[2]

            XCTAssertEqual(settingsItem.title, expectedSettingsTitle)
            XCTAssertTrue(separatorItem.isSeparatorItem)
            XCTAssertEqual(quitItem.title, expectedQuitTitle)

            XCTAssertTrue(settingsItem.target === MenuBarController.shared)
            XCTAssertNotNil(settingsItem.action)
            XCTAssertTrue(quitItem.target === MenuBarController.shared)
            XCTAssertNotNil(quitItem.action)

            XCTAssertNil(
                settingsItem.image,
                "设置项不应携带占位图或触发 AppKit 自动注入齿轮图标，否则会与退出项错位"
            )
            XCTAssertNil(quitItem.image, "退出项应保持纯文本格式")

            #if compiler(>=6.4)
            if #available(macOS 27.0, *) {
                XCTAssertEqual(settingsItem.preferredImageVisibility, .hidden)
            }
            #endif
        }
    }

    func testDropdownMenuSettingsLabelHasNoEllipsis() {
        XCTAssertEqual(I18n.localized("menu_settings", language: .zhHans), "设置")
        XCTAssertEqual(I18n.localized("menu_settings", language: .en), "Settings")
        XCTAssertEqual(I18n.localized("menu_settings_plain", language: .zhHans), "设置")
        XCTAssertEqual(I18n.localized("menu_settings_plain", language: .en), "Settings")
    }
}
