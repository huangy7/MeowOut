import XCTest
@testable import MeowOut

final class MemoSlashCommandTests: XCTestCase {
    func testTemplatesMatchMemosMarkdownSources() {
        XCTAssertEqual(MemoSlashCommand.todo.template, "- [ ] ")
        XCTAssertEqual(MemoSlashCommand.code.template, "```\n\n```")
        XCTAssertEqual(MemoSlashCommand.link.template, "[text](url)")
        XCTAssertEqual(MemoSlashCommand.table.template, "| Header | Header |\n| ------ | ------ |\n| Cell   | Cell |")
    }

    func testDisplayTextUsesSlashAndRawValue() {
        XCTAssertEqual(MemoSlashCommand.todo.displayText, "/todo")
        XCTAssertEqual(MemoSlashCommand.code.displayText, "/code")
        XCTAssertEqual(MemoSlashCommand.link.displayText, "/link")
        XCTAssertEqual(MemoSlashCommand.table.displayText, "/table")
    }

    func testCursorOffsetsPointIntoTemplates() {
        XCTAssertEqual(MemoSlashCommand.todo.cursorOffsetInTemplate, MemoSlashCommand.todo.template.count)
        XCTAssertEqual(MemoSlashCommand.code.cursorOffsetInTemplate, 4)
        XCTAssertEqual(MemoSlashCommand.link.cursorOffsetInTemplate, 1)
        XCTAssertEqual(MemoSlashCommand.table.cursorOffsetInTemplate, 1)
    }

    func testMatchingReturnsAllForEmptyQueryAndPrefixMatchesLowercasedInput() {
        XCTAssertEqual(MemoSlashCommand.matching(query: ""), [.todo, .code, .link, .table])
        XCTAssertEqual(MemoSlashCommand.matching(query: "CO"), [.code])
        XCTAssertEqual(MemoSlashCommand.matching(query: "ta"), [.table])
        XCTAssertEqual(MemoSlashCommand.matching(query: "x"), [])
    }

    func testApplyReplacesTriggerRangeAndReturnsAbsoluteCursorOffset() {
        let result = MemoSlashCommand.code.apply(to: "hello /co world", triggerRange: 6..<9)

        XCTAssertEqual(result.text, "hello ```\n\n``` world")
        XCTAssertEqual(result.cursorOffset, 10)
    }

    func testDetectsSlashWordImmediatelyBeforeCursor() {
        XCTAssertEqual(
            MemoSlashCommandTrigger.detect(in: "hello /co", cursorOffset: 9),
            MemoSlashCommandTrigger(query: "co", range: 6..<9)
        )
        XCTAssertEqual(
            MemoSlashCommandTrigger.detect(in: "/123", cursorOffset: 4),
            MemoSlashCommandTrigger(query: "123", range: 0..<4)
        )
        XCTAssertEqual(
            MemoSlashCommandTrigger.detect(in: "hello /", cursorOffset: 7),
            MemoSlashCommandTrigger(query: "", range: 6..<7)
        )
    }

    func testDetectRequiresSlashAtStartOrAfterWhitespace() {
        XCTAssertNil(MemoSlashCommandTrigger.detect(in: "hello/code", cursorOffset: 10))
        XCTAssertEqual(
            MemoSlashCommandTrigger.detect(in: "hello\n/code", cursorOffset: 11),
            MemoSlashCommandTrigger(query: "code", range: 6..<11)
        )
    }

    func testDetectIgnoresUrlsAndCursorAfterSpaceBeyondSlashWord() {
        XCTAssertNil(MemoSlashCommandTrigger.detect(in: "https://x.y/a", cursorOffset: 13))
        XCTAssertNil(MemoSlashCommandTrigger.detect(in: "hello /co now", cursorOffset: 13))
    }

    func testDetectsSlashTriggerBeforeCursor() {
        XCTAssertEqual(MemoSlashCommandTrigger.detect(in: "hello /co", cursorOffset: 9)?.query, "co")
        XCTAssertEqual(MemoSlashCommandTrigger.detect(in: "hello /co", cursorOffset: 9)?.range, 6..<9)
        XCTAssertNil(MemoSlashCommandTrigger.detect(in: "https://x.y/a", cursorOffset: 13))
        XCTAssertNil(MemoSlashCommandTrigger.detect(in: "hello /co now", cursorOffset: 13))
    }
}
