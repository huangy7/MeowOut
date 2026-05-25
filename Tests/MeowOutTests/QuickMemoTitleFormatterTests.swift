import XCTest
@testable import MeowOut

final class QuickMemoTitleFormatterTests: XCTestCase {
    func testTitleUsesFirstNonBlankLine() {
        XCTAssertEqual(
            QuickMemoTitleFormatter.title(for: "\n  范德萨发看看可以打下多少个字\n第二行"),
            "范德萨发看看可以打下多少个字"
        )
    }

    func testTitleFallsBackForBlankContent() {
        XCTAssertEqual(QuickMemoTitleFormatter.title(for: " \n\t "), I18n.localized("memos_quick_title_default"))
    }

    func testTitleTruncatesLongFirstLine() {
        XCTAssertEqual(
            QuickMemoTitleFormatter.title(for: "范德萨发看看可以打下多少个字，看看会不会太长", maxLength: 14),
            "范德萨发看看可以打下多少个字..."
        )
    }

    func testDefaultTitleKeepsEnoughCharactersForResizableToolbar() {
        XCTAssertEqual(
            QuickMemoTitleFormatter.title(for: "测试黄云测试标题字数测试黄云测试标题字数测试黄云测试标题字数"),
            "测试黄云测试标题字数测试黄云测试标题字数测试黄云测试标题字数"
        )
    }
}
