import XCTest
@testable import MeowOut

final class ClipboardAccessibilityPermissionTests: XCTestCase {
    func testOpenSettingsAfterPromptRequestsAccessibilityBeforeOpeningSettings() {
        var events: [String] = []

        ClipboardAccessibilityPermission.openSettingsAfterPrompt(
            requestPrompt: { events.append("prompt") },
            openSettings: { events.append("open") }
        )

        XCTAssertEqual(events, ["prompt", "open"])
    }
}
