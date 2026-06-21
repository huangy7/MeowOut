import XCTest
@testable import MeowOut

final class ClipboardShortcutCommandTests: XCTestCase {
    func testToggleShortcutDoesNothingWhenClipboardHistoryIsDisabled() {
        var toggleCount = 0

        let didHandle = ClipboardHistoryToggleCommand.handle(
            isEnabled: false,
            togglePanel: { toggleCount += 1 }
        )

        XCTAssertFalse(didHandle)
        XCTAssertEqual(toggleCount, 0)
    }

    func testToggleShortcutOpensPanelWhenClipboardHistoryIsEnabled() {
        var toggleCount = 0

        let didHandle = ClipboardHistoryToggleCommand.handle(
            isEnabled: true,
            togglePanel: { toggleCount += 1 }
        )

        XCTAssertTrue(didHandle)
        XCTAssertEqual(toggleCount, 1)
    }
}
