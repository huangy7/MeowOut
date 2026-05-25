import XCTest
@testable import MeowOut

final class CalendarMemoIndexTests: XCTestCase {
    private let gmtPlus8 = TimeZone(secondsFromGMT: 8 * 60 * 60)!

    func testGroupsDatesByLocalDayInGMTPlus8() {
        let index = CalendarMemoIndex(
            dates: [
                utcDate("2026-05-23T18:00:00Z"),
                utcDate("2026-05-24T03:00:00Z"),
                utcDate("2026-05-25T03:00:00Z")
            ],
            timeZone: gmtPlus8
        )

        XCTAssertEqual(index.count(for: "2026-05-24"), 2)
        XCTAssertEqual(index.count(for: "2026-05-25"), 1)
    }

    func testCountAndSelectableForMissingDay() {
        let index = CalendarMemoIndex(
            dates: [utcDate("2026-05-24T03:00:00Z")],
            timeZone: gmtPlus8
        )

        XCTAssertEqual(index.count(for: "2026-05-24"), 1)
        XCTAssertTrue(index.isSelectable("2026-05-24"))
        XCTAssertEqual(index.count(for: "2026-05-23"), 0)
        XCTAssertFalse(index.isSelectable("2026-05-23"))
    }

    func testDatesInMonthReturnsOnlyMatchingLocalMonthKeysSorted() {
        let index = CalendarMemoIndex(
            dates: [
                utcDate("2026-05-24T03:00:00Z"),
                utcDate("2026-04-30T16:00:00Z"),
                utcDate("2026-05-31T16:00:00Z"),
                utcDate("2026-05-01T00:00:00Z")
            ],
            timeZone: gmtPlus8
        )

        XCTAssertEqual(index.dates(inMonth: "2026-05"), [
            "2026-05-01",
            "2026-05-24"
        ])
    }

    func testDuplicateDatesCountCorrectly() {
        let duplicate = utcDate("2026-05-24T03:00:00Z")
        let index = CalendarMemoIndex(
            dates: [duplicate, duplicate, utcDate("2026-05-24T15:59:59Z")],
            timeZone: gmtPlus8
        )

        XCTAssertEqual(index.count(for: "2026-05-24"), 3)
    }

    private func utcDate(_ iso8601: String) -> Date {
        ISO8601DateFormatter().date(from: iso8601)!
    }
}
