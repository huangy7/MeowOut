import AppKit
import XCTest
@testable import MeowOut

@MainActor
final class MemosBrowserWindowControllerTests: XCTestCase {
    func testWindowInitialSizeAndMinSize() {
        let controller = MemosBrowserWindowController.shared
        guard let window = controller.window else {
            XCTFail("MemosBrowserWindowController window should exist")
            return
        }

        XCTAssertGreaterThanOrEqual(window.contentRect(forFrameRect: window.frame).width, 1200, "Window width should be at least 1200 to accommodate multi-column layout")
        XCTAssertGreaterThanOrEqual(window.minSize.width, 1160, "Window minSize width should be at least 1160 to prevent navigation rail clipping")
        XCTAssertGreaterThanOrEqual(window.minSize.height, 600, "Window minSize height should be at least 600")
        XCTAssertEqual(window.frameAutosaveName, "MeowOutMemosBrowserWindow", "Window should persist its frame size and position")
    }
}
