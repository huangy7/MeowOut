import SwiftUI
import MemosKit

struct MemoCalendarSidebarView: View {
    @Environment(AppState.self) private var appState
    @Binding var filter: MemoFilterState
    let calendarIndex: CalendarMemoIndex
    let allTags: [String]
    let treatsArchivedAsBaseState: Bool
    let isRefreshing: Bool
    let onRefresh: () -> Void

    @State private var visibleMonth = Date()
    private let calendar = Calendar.current
    private let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("搜索备忘...", text: $filter.searchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                    }
                    .padding(10)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(10)

                    RefreshIconButton(
                        isRefreshing: isRefreshing,
                        accessibilityLabel: hasResettableFilters ? "重置过滤并同步" : "同步 Memos",
                        help: hasResettableFilters ? "重置过滤并同步" : "同步 Memos",
                        action: onRefresh
                    )
                    .frame(width: 30, height: 30)
                    .disabled(isRefreshing)
                    .opacity(isRefreshing ? 0.7 : 1)
                    .animation(.easeInOut(duration: 0.12), value: isRefreshing)
                    .animation(.easeInOut(duration: 0.12), value: filter.hasActiveFilters)
                    .overlay(alignment: .topTrailing) {
                        if hasResettableFilters {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 6, height: 6)
                                .offset(x: -2, y: 2)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                }

                MemoFilterChipsView(filter: $filter)
            }

            // Calendar Section
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(monthTitle)
                        .font(.system(size: 13, weight: .bold))
                    Spacer()
                    Button(action: { changeMonth(by: -1) }) {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.plain)
                    Button(action: { changeMonth(by: 1) }) {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 4)
                
                VStack(spacing: 4) {
                    // Week headers
                    HStack(spacing: 0) {
                        ForEach(["日", "一", "二", "三", "四", "五", "六"], id: \.self) { day in
                            Text(day)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    
                    // Days grid
                    let days = daysInMonth()
                    let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
                    
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(days, id: \.self) { date in
                            if let date = date {
                                DayCell(
                                    date: date,
                                    isSelected: calendar.isDate(date, inSameDayAs: filter.selectedDate ?? Date(timeIntervalSince1970: 0)),
                                    hasMemos: calendarIndex.count(for: key(for: date)) > 0,
                                    action: {
                                        if let selected = filter.selectedDate, calendar.isDate(selected, inSameDayAs: date) {
                                            filter.selectedDate = nil
                                        } else {
                                            filter.selectedDate = date
                                        }
                                    }
                                )
                            } else {
                                Color.clear.frame(width: 24, height: 24)
                            }
                        }
                    }
                }
            }
            .padding(10)
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(12)

            // Tags Section
            VStack(alignment: .leading, spacing: 10) {
                Text(I18n.localized("memos_editor_format_tag", language: appState.language))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                
                ScrollView {
                    SidebarFlowLayout(spacing: 8) {
                        ForEach(allTags, id: \.self) { tag in
                            TagButton(tag: tag, isSelected: filter.selectedTag == tag) {
                                if filter.selectedTag == tag {
                                    filter.selectedTag = nil
                                } else {
                                    filter.selectedTag = tag
                                }
                            }
                        }
                    }
                    .padding(4)
                }
            }

            Spacer()
        }
        .padding(16)
        .frame(width: 260)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var hasResettableFilters: Bool {
        !filter.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !(filter.selectedTag?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            || filter.selectedDate != nil
            || (!treatsArchivedAsBaseState && filter.showArchived)
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年 M月"
        return formatter.string(from: visibleMonth)
    }

    private func changeMonth(by value: Int) {
        if let next = calendar.date(byAdding: .month, value: value, to: visibleMonth) {
            visibleMonth = next
        }
    }

    private func daysInMonth() -> [Date?] {
        guard let monthRange = calendar.range(of: .day, in: .month, for: visibleMonth),
              let firstDayOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: visibleMonth))
        else { return [] }

        let weekdayOfFirstDay = calendar.component(.weekday, from: firstDayOfMonth)
        var days: [Date?] = Array(repeating: nil, count: weekdayOfFirstDay - 1)

        for day in monthRange {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: firstDayOfMonth) {
                days.append(date)
            }
        }

        while days.count % 7 != 0 {
            days.append(nil)
        }

        return days
    }

    private func key(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

struct RefreshIconButton: View {
    let isRefreshing: Bool
    let accessibilityLabel: String
    let help: String
    let action: () -> Void

    @State private var rotation: Double = 0

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.42)) {
                rotation += RefreshIconButtonRotation.tapIncrement
            }
            action()
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 15, weight: .semibold))
                .rotationEffect(.degrees(rotation))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(accessibilityLabel)
        .onChange(of: isRefreshing) { _, refreshing in
            if !refreshing {
                rotation = RefreshIconButtonRotation.normalized(rotation)
            }
        }
    }
}

enum RefreshIconButtonRotation {
    static let tapIncrement: Double = 360

    static func normalized(_ rotation: Double) -> Double {
        rotation.truncatingRemainder(dividingBy: 360)
    }
}

struct DayCell: View {
    let date: Date
    let isSelected: Bool
    let hasMemos: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("\(Calendar.current.component(.day, from: date))")
                .font(.system(size: 11, weight: isSelected ? .bold : .regular))
                .frame(width: 24, height: 24)
                .background(isSelected ? Color.accentColor : (hasMemos ? Color.accentColor.opacity(0.15) : Color.clear))
                .foregroundStyle(isSelected ? .white : (hasMemos ? .primary : .secondary))
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

struct TagButton: View {
    let tag: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("#\(tag)")
                .font(.system(size: 12))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.1))
                .foregroundStyle(isSelected ? .white : .primary)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

struct SidebarFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > width {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            maxWidth = max(maxWidth, currentX)
        }
        return CGSize(width: maxWidth, height: currentY + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX: CGFloat = bounds.minX
        var currentY: CGFloat = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX {
                currentX = bounds.minX
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: .unspecified)
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
