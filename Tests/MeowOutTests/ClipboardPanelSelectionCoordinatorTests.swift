import XCTest
@testable import MeowOut

@MainActor
final class ClipboardPanelSelectionCoordinatorTests: XCTestCase {
    func testChooseRunsAfterDismissOnNextMainQueueTurn() {
        var events: [String] = []
        let chooseExpectation = expectation(description: "choose runs asynchronously")

        ClipboardPanelSelectionCoordinator.chooseAfterDismiss(
            dismiss: {
                events.append("dismiss")
            },
            choose: {
                events.append("choose")
                chooseExpectation.fulfill()
            }
        )

        XCTAssertEqual(events, ["dismiss"])

        wait(for: [chooseExpectation], timeout: 1)
        XCTAssertEqual(events, ["dismiss", "choose"])
    }
}
