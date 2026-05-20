import XCTest
import SwiftUI
@testable import MeowOut

final class PillTabBarTests: XCTestCase {
    func testInitialization() {
        let items = ["Tab 1", "Tab 2"]
        let selection = Binding.constant("Tab 1")
        let view = PillTabBar(items: items, selection: selection)
        
        XCTAssertNotNil(view)
        XCTAssertEqual(view.items, items)
    }
}
