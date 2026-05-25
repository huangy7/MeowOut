import Foundation

public struct CalendarMemoIndex: Equatable, Sendable {
    public private(set) var countsByDate: [String: Int]

    public init(dates: [Date], timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"

        self.countsByDate = dates.reduce(into: [:]) { counts, date in
            counts[formatter.string(from: date), default: 0] += 1
        }
    }

    public func count(for yyyyMMdd: String) -> Int {
        countsByDate[yyyyMMdd, default: 0]
    }

    public func isSelectable(_ yyyyMMdd: String) -> Bool {
        count(for: yyyyMMdd) > 0
    }

    public func dates(inMonth yyyyMM: String) -> [String] {
        let prefix = "\(yyyyMM)-"
        return countsByDate.keys
            .filter { $0.hasPrefix(prefix) }
            .sorted()
    }
}
