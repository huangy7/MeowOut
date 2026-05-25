import XCTest
@testable import MeowOut

final class MemoFilterChipsTests: XCTestCase {
    func testActiveChipsReturnSearchTagDateOrderWithFormattedTitles() {
        var state = MemoFilterState()
        state.searchText = " daily "
        state.selectedTag = " work "
        state.selectedDate = makeUTCDate(year: 2026, month: 5, day: 24, hour: 15)

        let chips = MemoFilterChip.activeChips(for: state, calendar: utcCalendar)

        XCTAssertEqual(
            chips,
            [
                MemoFilterChip(kind: .search, title: "daily"),
                MemoFilterChip(kind: .tag, title: "#work"),
                MemoFilterChip(kind: .date, title: "2026-05-24")
            ]
        )
    }

    func testActiveChipsIgnoreBlankSearchAndTag() {
        var state = MemoFilterState()
        state.searchText = " \n\t "
        state.selectedTag = "   "

        XCTAssertEqual(MemoFilterChip.activeChips(for: state, calendar: utcCalendar), [])
    }

    func testClearingSingleChipClearsOnlyThatField() {
        let selectedDate = makeUTCDate(year: 2026, month: 5, day: 24, hour: 15)
        var state = MemoFilterState(
            searchText: "daily",
            selectedTag: "work",
            selectedDate: selectedDate,
            showArchived: true
        )

        MemoFilterChip.Kind.tag.clear(from: &state)

        XCTAssertEqual(state.searchText, "daily")
        XCTAssertNil(state.selectedTag)
        XCTAssertEqual(state.selectedDate, selectedDate)
        XCTAssertTrue(state.showArchived)
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func makeUTCDate(year: Int, month: Int, day: Int, hour: Int) -> Date {
        DateComponents(
            calendar: utcCalendar,
            timeZone: TimeZone(secondsFromGMT: 0),
            year: year,
            month: month,
            day: day,
            hour: hour
        ).date!
    }
}
