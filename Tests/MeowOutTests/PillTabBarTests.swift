import XCTest
import SwiftUI
@testable import MeowOut

final class PillTabBarTests: XCTestCase {
    func testInitialization() {
        let items = [PillTabItem(id: "tab1", title: "Tab 1"), PillTabItem(id: "tab2", title: "Tab 2")]
        let selection = Binding.constant("tab1")
        let view = PillTabBar(items: items, selection: selection)

        XCTAssertNotNil(view)
        XCTAssertEqual(view.items, items)
    }

    func testSelectionUsesStableId() {
        // 展示文案(可能随语言变化)与选中标识(稳定 id)应当解耦
        let items = [PillTabItem(id: "work_rest", title: "工作休息"), PillTabItem(id: "water", title: "喝水")]
        let selection = Binding.constant("water")
        let view = PillTabBar(items: items, selection: selection)

        XCTAssertEqual(view.selection, "water")
        XCTAssertEqual(view.items.map(\.id), ["work_rest", "water"])
    }
}
