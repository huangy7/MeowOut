import XCTest
@testable import MeowOut

@MainActor
final class KeyDropWorkspaceStateTests: XCTestCase {

    func testFilteredSnippetsByCategoryAndCaseInsensitiveQuery() {
        let s1 = Snippet(title: "Work Email", content: "alex@company.com", category: "工作")
        let s2 = Snippet(title: "PR Template", content: "1. Summary\n2. Verification", category: "开发")
        let s3 = Snippet(title: "Phone", content: "13800138000", category: KeyDropConstants.categoryUncategorized)
        let all = [s1, s2, s3]

        let browse = KeyDropBrowseState()
        XCTAssertEqual(browse.filteredSnippets(from: all), all)

        browse.selectedCategory = "开发"
        XCTAssertEqual(browse.filteredSnippets(from: all), [s2])

        browse.selectedCategory = KeyDropConstants.categoryAll
        browse.searchText = "COMPANY"
        XCTAssertEqual(browse.filteredSnippets(from: all), [s1])

        browse.searchText = "verification"
        XCTAssertEqual(browse.filteredSnippets(from: all), [s2])

        browse.searchText = "no-match-xyz"
        XCTAssertTrue(browse.filteredSnippets(from: all).isEmpty)
    }

    func testReconciledSelectionKeepsValidOrFallsBackToFirst() {
        let s1 = Snippet(title: "One", content: "1")
        let s2 = Snippet(title: "Two", content: "2")
        let missingID = UUID()

        XCTAssertEqual(
            KeyDropBrowseState.reconciledSelection(currentID: s2.id, in: [s1, s2]),
            s2.id
        )
        XCTAssertEqual(
            KeyDropBrowseState.reconciledSelection(currentID: missingID, in: [s1, s2]),
            s1.id
        )
        XCTAssertEqual(
            KeyDropBrowseState.reconciledSelection(currentID: nil, in: [s1, s2]),
            s1.id
        )
        XCTAssertNil(
            KeyDropBrowseState.reconciledSelection(currentID: s1.id, in: [])
        )
    }

    func testSelectionAfterDeletingPrefersNextThenPrevious() {
        let s1 = Snippet(title: "One", content: "1")
        let s2 = Snippet(title: "Two", content: "2")
        let s3 = Snippet(title: "Three", content: "3")

        // Deleting middle item selects the following item
        XCTAssertEqual(
            KeyDropBrowseState.selectionAfterDeleting(id: s2.id, in: [s1, s2, s3]),
            s3.id
        )
        // Deleting last item selects the previous item
        XCTAssertEqual(
            KeyDropBrowseState.selectionAfterDeleting(id: s3.id, in: [s1, s2, s3]),
            s2.id
        )
        // Deleting first item selects the new first item
        XCTAssertEqual(
            KeyDropBrowseState.selectionAfterDeleting(id: s1.id, in: [s1, s2, s3]),
            s2.id
        )
        // Deleting the only item yields nil
        XCTAssertNil(
            KeyDropBrowseState.selectionAfterDeleting(id: s1.id, in: [s1])
        )
    }

    func testNeighborSelectionMovingUpAndDownClampsAtBounds() {
        let s1 = Snippet(title: "One", content: "1")
        let s2 = Snippet(title: "Two", content: "2")
        let s3 = Snippet(title: "Three", content: "3")
        let list = [s1, s2, s3]

        XCTAssertEqual(KeyDropBrowseState.movedSelection(currentID: nil, delta: 1, in: list), s1.id)
        XCTAssertEqual(KeyDropBrowseState.movedSelection(currentID: nil, delta: -1, in: list), s3.id)
        XCTAssertEqual(KeyDropBrowseState.movedSelection(currentID: s1.id, delta: 1, in: list), s2.id)
        XCTAssertEqual(KeyDropBrowseState.movedSelection(currentID: s3.id, delta: 1, in: list), s3.id)
        XCTAssertEqual(KeyDropBrowseState.movedSelection(currentID: s1.id, delta: -1, in: list), s1.id)
        XCTAssertEqual(KeyDropBrowseState.movedSelection(currentID: s2.id, delta: -1, in: list), s1.id)
        XCTAssertNil(KeyDropBrowseState.movedSelection(currentID: s1.id, delta: 1, in: []))
    }

    func testDraftValidationAndAutoTitleExtraction() {
        let emptyDraft = SnippetDraft(title: "  ", content: " \n ", category: "开发")
        XCTAssertFalse(emptyDraft.canSave)
        XCTAssertFalse(emptyDraft.hasUnsavedInput)

        let titleOnlyDraft = SnippetDraft(title: "Only Title", content: "  ", category: "开发")
        XCTAssertFalse(titleOnlyDraft.canSave)
        XCTAssertTrue(titleOnlyDraft.hasUnsavedInput)

        let contentOnlyDraft = SnippetDraft(
            title: "   ",
            content: "\n   First meaningful line for snippet   \nSecond line",
            category: "开发"
        )
        XCTAssertTrue(contentOnlyDraft.canSave)
        XCTAssertTrue(contentOnlyDraft.hasUnsavedInput)
        XCTAssertEqual(contentOnlyDraft.resolvedTitle, "First meaningful line fo")

        let explicitTitleDraft = SnippetDraft(title: "  My Snippet  ", content: "Body", category: "")
        XCTAssertEqual(explicitTitleDraft.resolvedTitle, "My Snippet")
        XCTAssertEqual(explicitTitleDraft.resolvedCategory, KeyDropConstants.categoryUncategorized)

        let built = explicitTitleDraft.makeSnippet()
        XCTAssertEqual(built.title, "My Snippet")
        XCTAssertEqual(built.content, "Body")
        XCTAssertEqual(built.category, KeyDropConstants.categoryUncategorized)
    }

    func testContentMetricsCountsLinesAndCharacters() {
        let empty = SnippetContentMetrics.measure("")
        XCTAssertEqual(empty.lineCount, 0)
        XCTAssertEqual(empty.characterCount, 0)

        let single = SnippetContentMetrics.measure("hello")
        XCTAssertEqual(single.lineCount, 1)
        XCTAssertEqual(single.characterCount, 5)

        let multi = SnippetContentMetrics.measure("line 1\nline 2\nline 3")
        XCTAssertEqual(multi.lineCount, 3)
        XCTAssertEqual(multi.characterCount, 20)

        let trailingNewline = SnippetContentMetrics.measure("line 1\n")
        XCTAssertEqual(trailingNewline.lineCount, 2)
        XCTAssertEqual(trailingNewline.characterCount, 7)
    }

    func testCategoryPaletteIndexIsDeterministicAndNeutralForUncategorized() {
        XCTAssertNil(SnippetCategoryStyle.paletteIndex(for: KeyDropConstants.categoryUncategorized))
        XCTAssertNil(SnippetCategoryStyle.paletteIndex(for: ""))
        XCTAssertNil(SnippetCategoryStyle.paletteIndex(for: KeyDropConstants.categoryAll))

        let workIndex1 = SnippetCategoryStyle.paletteIndex(for: "工作")
        let workIndex2 = SnippetCategoryStyle.paletteIndex(for: "工作")
        XCTAssertNotNil(workIndex1)
        XCTAssertEqual(workIndex1, workIndex2)
    }

    func testSettingsWindowFrameCalculatorExpandsAnchoredAtTopLeft() {
        let current = CGRect(x: 200, y: 300, width: 660, height: 580) // maxY = 880
        let screen = CGRect(x: 0, y: 40, width: 1440, height: 860)     // maxY = 900

        let expanded = SettingsWindowFrameCalculator.frameAnchoredTopLeft(
            current: current,
            targetSize: CGSize(width: 860, height: 620),
            visibleScreenFrame: screen
        )

        XCTAssertEqual(expanded.width, 860)
        XCTAssertEqual(expanded.height, 620)
        XCTAssertEqual(expanded.origin.x, 200)
        XCTAssertEqual(expanded.maxY, 880)
    }

    func testSettingsWindowFrameCalculatorClampsInsideVisibleScreen() {
        let current = CGRect(x: 750, y: 50, width: 660, height: 580) // maxY = 630
        let screen = CGRect(x: 0, y: 40, width: 1440, height: 860)

        let expanded = SettingsWindowFrameCalculator.frameAnchoredTopLeft(
            current: current,
            targetSize: CGSize(width: 860, height: 620),
            visibleScreenFrame: screen
        )

        XCTAssertEqual(expanded.width, 860)
        XCTAssertEqual(expanded.height, 620)
        XCTAssertLessThanOrEqual(expanded.maxX, screen.maxX)
        XCTAssertGreaterThanOrEqual(expanded.minY, screen.minY)
    }

    func testSettingsWindowFrameCalculatorRestoresCompactSize() {
        let expanded = CGRect(x: 200, y: 260, width: 860, height: 620) // maxY = 880
        let screen = CGRect(x: 0, y: 40, width: 1440, height: 860)

        let restored = SettingsWindowFrameCalculator.frameAnchoredTopLeft(
            current: expanded,
            targetSize: CGSize(width: 660, height: 580),
            visibleScreenFrame: screen
        )

        XCTAssertEqual(restored, CGRect(x: 200, y: 300, width: 660, height: 580))
    }
}
