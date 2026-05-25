import Foundation
import SwiftUI

public struct MemoFilterChip: Identifiable, Equatable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case search
        case tag
        case date

        public func clear(from state: inout MemoFilterState) {
            switch self {
            case .search:
                state.searchText = ""
            case .tag:
                state.selectedTag = nil
            case .date:
                state.selectedDate = nil
            }
        }
    }

    public var id: Kind { kind }
    public var kind: Kind
    public var title: String

    public init(kind: Kind, title: String) {
        self.kind = kind
        self.title = title
    }

    public static func activeChips(for state: MemoFilterState, calendar: Calendar) -> [MemoFilterChip] {
        var chips: [MemoFilterChip] = []

        let trimmedSearchText = state.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSearchText.isEmpty {
            chips.append(MemoFilterChip(kind: .search, title: trimmedSearchText))
        }

        if let selectedTag = state.selectedTag {
            let trimmedTag = selectedTag.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedTag.isEmpty {
                chips.append(MemoFilterChip(kind: .tag, title: "#\(trimmedTag)"))
            }
        }

        if let selectedDate = state.selectedDate {
            chips.append(MemoFilterChip(
                kind: .date,
                title: formattedDate(selectedDate, calendar: calendar)
            ))
        }

        return chips
    }

    private static func formattedDate(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

public struct MemoFilterChipsView: View {
    @Binding private var filter: MemoFilterState
    private let calendar: Calendar

    public init(filter: Binding<MemoFilterState>, calendar: Calendar = .current) {
        self._filter = filter
        self.calendar = calendar
    }

    public var body: some View {
        let chips = MemoFilterChip.activeChips(for: filter, calendar: calendar)

        if !chips.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(chips) { chip in
                        chipView(chip)
                    }

                    if chips.count > 1 {
                        Button("清除全部") {
                            clear(chips)
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
    }

    private func chipView(_ chip: MemoFilterChip) -> some View {
        HStack(spacing: 6) {
            Text(chip.title)
                .font(.caption)
                .lineLimit(1)

            Button {
                chip.kind.clear(from: &filter)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.semibold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("清除 \(chip.title)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.quaternary, in: Capsule())
    }

    private func clear(_ chips: [MemoFilterChip]) {
        for chip in chips {
            chip.kind.clear(from: &filter)
        }
    }
}
