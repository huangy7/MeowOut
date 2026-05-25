import Foundation
import MemosKit

public struct MemoFilterState: Equatable, Sendable {
    public var searchText: String
    public var selectedTag: String?
    public var selectedDate: Date?
    public var showArchived: Bool

    public init(
        searchText: String = "",
        selectedTag: String? = nil,
        selectedDate: Date? = nil,
        showArchived: Bool = false
    ) {
        self.searchText = searchText
        self.selectedTag = selectedTag
        self.selectedDate = selectedDate
        self.showArchived = showArchived
    }

    public var celFilter: String? {
        celFilter(timeZone: .current)
    }

    @available(*, deprecated, renamed: "celFilter")
    public var filter: String? {
        celFilter
    }

    public var memoState: MemosKit.MemoState {
        showArchived ? .archived : .normal
    }

    public var hasActiveFilters: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !(selectedTag?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            || selectedDate != nil
            || showArchived
    }

    public func celFilter(timeZone: TimeZone) -> String? {
        var parts: [String] = []

        let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSearchText.isEmpty {
            parts.append("content.contains(\(Self.jsonString(trimmedSearchText)))")
        }

        if let selectedTag {
            let trimmedTag = selectedTag.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedTag.isEmpty {
                parts.append("tag in [\(Self.jsonString(trimmedTag))]")
            }
        }

        if let selectedDate {
            let range = dayRange(for: selectedDate, timeZone: timeZone)
            parts.append("created_ts >= \(range.start) && created_ts < \(range.end)")
        }

        return parts.isEmpty ? nil : parts.joined(separator: " && ")
    }

    @available(*, deprecated, renamed: "celFilter(timeZone:)")
    public func filter(timeZone: TimeZone) -> String? {
        celFilter(timeZone: timeZone)
    }

    public mutating func reset() {
        searchText = ""
        selectedTag = nil
        selectedDate = nil
        showArchived = false
    }

    private func dayRange(for date: Date, timeZone: TimeZone) -> (start: Int, end: Int) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!

        return (Int(start.timeIntervalSince1970), Int(end.timeIntervalSince1970))
    }

    private static func jsonString(_ value: String) -> String {
        let data = try! JSONEncoder().encode(value)
        return String(decoding: data, as: UTF8.self)
    }
}
