import XCTest
@testable import MeowOut

final class MemoFilterStateTests: XCTestCase {
    private let shanghai = TimeZone(secondsFromGMT: 8 * 60 * 60)!

    func testEmptyFilterReturnsNil() {
        let state = MemoFilterState()

        XCTAssertNil(state.celFilter(timeZone: shanghai))
        XCTAssertNil(state.celFilter)
    }

    func testSearchTextUsesJSONStringEscaping() throws {
        var state = MemoFilterState()
        state.searchText = "hello \"memo\"\\ path\\line\nnext"

        XCTAssertEqual(
            state.celFilter(timeZone: shanghai),
            "content.contains(\(try jsonString(state.searchText)))"
        )
    }

    func testSearchTextTrimsWhitespaceBeforeEncoding() throws {
        var state = MemoFilterState()
        state.searchText = " \n daily note \t "

        XCTAssertEqual(
            state.celFilter(timeZone: shanghai),
            "content.contains(\(try jsonString("daily note")))"
        )

        state.searchText = " \n\t "

        XCTAssertNil(state.celFilter(timeZone: shanghai))
    }

    func testSelectedTagUsesOfficialTagExpression() throws {
        var state = MemoFilterState()
        state.selectedTag = #"灵感 "quote"\tag"#

        XCTAssertEqual(
            state.celFilter(timeZone: shanghai),
            "tag in [\(try jsonString(state.selectedTag!))]"
        )
    }

    func testSelectedTagTrimsWhitespaceBeforeEncoding() throws {
        var state = MemoFilterState()
        state.selectedTag = " \n work/tag \t "

        XCTAssertEqual(
            state.celFilter(timeZone: shanghai),
            "tag in [\(try jsonString("work/tag"))]"
        )

        state.selectedTag = " \n\t "

        XCTAssertNil(state.celFilter(timeZone: shanghai))
    }

    func testSelectedDateUsesProvidedTimeZoneDayRange() {
        var state = MemoFilterState()
        state.selectedDate = makeDate(year: 2026, month: 5, day: 24, hour: 12, minute: 30, timeZone: shanghai)

        let expectedStart = utcTimestamp(year: 2026, month: 5, day: 23, hour: 16)
        let expectedEnd = utcTimestamp(year: 2026, month: 5, day: 24, hour: 16)

        XCTAssertEqual(
            state.celFilter(timeZone: shanghai),
            "created_ts >= \(expectedStart) && created_ts < \(expectedEnd)"
        )
    }

    func testCombinedFilterOrderIsSearchTagDate() throws {
        var state = MemoFilterState()
        state.searchText = " daily "
        state.selectedTag = " work "
        state.selectedDate = makeDate(year: 2026, month: 5, day: 24, hour: 8, timeZone: shanghai)

        let expectedStart = utcTimestamp(year: 2026, month: 5, day: 23, hour: 16)
        let expectedEnd = utcTimestamp(year: 2026, month: 5, day: 24, hour: 16)

        XCTAssertEqual(
            state.celFilter(timeZone: shanghai),
            [
                "content.contains(\(try jsonString("daily")))",
                "tag in [\(try jsonString("work"))]",
                "created_ts >= \(expectedStart) && created_ts < \(expectedEnd)"
            ].joined(separator: " && ")
        )
    }

    func testResetAndMemoStateBehavior() {
        var state = MemoFilterState(
            searchText: "daily",
            selectedTag: "work",
            selectedDate: Date(),
            showArchived: true
        )

        XCTAssertEqual(state.memoState.rawValue, "ARCHIVED")

        state.reset()

        XCTAssertEqual(state.searchText, "")
        XCTAssertNil(state.selectedTag)
        XCTAssertNil(state.selectedDate)
        XCTAssertFalse(state.showArchived)
        XCTAssertEqual(state.memoState.rawValue, "NORMAL")
    }

    func testHasActiveFiltersIgnoresBlankTextAndTracksFilterFields() {
        var state = MemoFilterState(searchText: " \n\t ")
        XCTAssertFalse(state.hasActiveFilters)

        state.searchText = "daily"
        XCTAssertTrue(state.hasActiveFilters)

        state.searchText = ""
        state.selectedTag = " \t "
        XCTAssertFalse(state.hasActiveFilters)

        state.selectedTag = "work"
        XCTAssertTrue(state.hasActiveFilters)

        state.selectedTag = nil
        state.selectedDate = Date()
        XCTAssertTrue(state.hasActiveFilters)

        state.selectedDate = nil
        state.showArchived = true
        XCTAssertTrue(state.hasActiveFilters)
    }

    private func makeDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int = 0,
        timeZone: TimeZone
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(
            timeZone: timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }

    private func utcTimestamp(year: Int, month: Int, day: Int, hour: Int) -> Int {
        Int(DateComponents(
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(secondsFromGMT: 0),
            year: year,
            month: month,
            day: day,
            hour: hour
        ).date!.timeIntervalSince1970)
    }

    private func jsonString(_ value: String) throws -> String {
        let data = try JSONEncoder().encode(value)
        return String(decoding: data, as: UTF8.self)
    }
}
