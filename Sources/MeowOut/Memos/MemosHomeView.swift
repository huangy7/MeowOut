import SwiftUI
import MemosKit

struct MemosHomeView: View {
    @Environment(AppState.self) private var appState

    @State private var filter = MemoFilterState()
    @State private var calendarIndex = CalendarMemoIndex(dates: [])
    @State private var selectedMemo: Memo?
    @State private var filterVisible = true
    @State private var isLoadingStats = false
    @State private var isRefreshingAll = false

    let mode: MemosCollectionMode

    init(mode: MemosCollectionMode = .normal) {
        self.mode = mode
        _filter = State(initialValue: MemoFilterState(showArchived: mode == .archived))
    }

    var body: some View {
        HStack(spacing: 0) {
            if filterVisible {
                MemoCalendarSidebarView(
                    filter: $filter,
                    calendarIndex: calendarIndex,
                    allTags: appState.memosTagHistory,
                    treatsArchivedAsBaseState: mode == .archived,
                    isRefreshing: isRefreshingAll,
                    onRefresh: refreshAll
                )
                .frame(width: 260)

                Divider()
            }

            MemoListColumnView(
                mode: mode,
                filter: filter,
                showsFilterSummary: !filterVisible,
                showsRefreshButton: !filterVisible,
                isExternalRefreshing: isRefreshingAll,
                selectedMemo: $selectedMemo,
                onToggleFilter: {
                    withAnimation(.snappy(duration: 0.18)) {
                        filterVisible.toggle()
                    }
                },
                onRefresh: refreshAll
            )
            .frame(minWidth: 340, idealWidth: 400, maxWidth: 460)

            Divider()

            MemoDetailView(memo: $selectedMemo, mode: mode)
                .frame(minWidth: 480)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear { loadStats() }
        .onReceive(NotificationCenter.default.publisher(for: .memosDidChange)) { _ in
            loadStats()
        }
    }

    private func loadStats() {
        guard !isLoadingStats else {
            isRefreshingAll = false
            return
        }
        isLoadingStats = true

        Task {
            do {
                let user = try await MemosClient.shared.getCurrentUser()
                let stats = try await MemosClient.shared.getUserStats(userName: user.name)
                await MainActor.run {
                    calendarIndex = CalendarMemoIndex(dates: stats.memoCreatedTimestamps)
                    appState.memosTagHistory = Array(stats.tagCount.keys).sorted()
                    isLoadingStats = false
                    isRefreshingAll = false
                }
            } catch {
                await MainActor.run {
                    calendarIndex = CalendarMemoIndex(dates: [])
                    isLoadingStats = false
                    isRefreshingAll = false
                }
            }
        }
    }

    private func refreshAll() {
        guard !isRefreshingAll else { return }
        if hasResettableFilters {
            withAnimation(.snappy(duration: 0.16)) {
                resetFiltersForCurrentMode()
            }
        }
        isRefreshingAll = true
        NotificationCenter.default.post(name: .memosDidChange, object: nil)
    }

    private func resetFiltersForCurrentMode() {
        filter.searchText = ""
        filter.selectedTag = nil
        filter.selectedDate = nil
        filter.showArchived = mode == .archived
    }

    private var hasResettableFilters: Bool {
        !filter.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !(filter.selectedTag?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            || filter.selectedDate != nil
            || (mode != .archived && filter.showArchived)
    }
}
