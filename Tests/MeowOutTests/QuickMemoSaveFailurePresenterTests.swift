import XCTest
import MemosKit
@testable import MeowOut

final class QuickMemoSaveFailurePresenterTests: XCTestCase {
    func testNotConfiguredFailurePromptsSettingsAction() {
        let presentation = QuickMemoSaveFailurePresenter.presentation(for: MemosError.notConfigured)

        XCTAssertEqual(presentation.message, I18n.localized("memos_error_not_configured"))
        XCTAssertEqual(presentation.actionTitle, I18n.localized("memos_action_go_to_settings"))
        XCTAssertTrue(presentation.opensMemosSettings)
    }

    func testUnauthorizedFailurePromptsSettingsAction() {
        let presentation = QuickMemoSaveFailurePresenter.presentation(for: MemosError.unauthorized)

        XCTAssertEqual(presentation.message, I18n.localized("memos_error_unauthorized"))
        XCTAssertEqual(presentation.actionTitle, I18n.localized("memos_action_go_to_settings"))
        XCTAssertTrue(presentation.opensMemosSettings)
    }
}
