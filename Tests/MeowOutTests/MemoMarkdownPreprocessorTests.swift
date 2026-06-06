import XCTest
@testable import MeowOut

final class MemoMarkdownPreprocessorTests: XCTestCase {
    func testAddsMarkdownHardBreaksForSingleNewlines() {
        XCTAssertEqual(
            MemoMarkdownPreprocessor.renderableMarkdown(from: "第一行\n第二行\n第三行"),
            "第一行  \n第二行  \n第三行"
        )
    }

    func testKeepsBlankLinesAsParagraphBreaks() {
        XCTAssertEqual(
            MemoMarkdownPreprocessor.renderableMarkdown(from: "第一段\n\n第二段"),
            "第一段  \n\n第二段"
        )
    }

    func testDoesNotAddHardBreaksInsideFencedCodeBlocks() {
        XCTAssertEqual(
            MemoMarkdownPreprocessor.renderableMarkdown(from: "说明\n```\na\nb\n```\n结束"),
            "说明  \n```\na\nb\n```\n结束"
        )
    }
}
