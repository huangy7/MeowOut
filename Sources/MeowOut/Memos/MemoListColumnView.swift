import SwiftUI
import MemosKit

struct MemoListColumnView: View {
    @Environment(AppState.self) private var appState

    @State private var viewModel = MemoTimelineViewModel()

    let mode: MemosCollectionMode
    let filter: MemoFilterState
    let showsFilterSummary: Bool
    let showsRefreshButton: Bool
    let isExternalRefreshing: Bool
    @Binding var selectedMemo: Memo?
    let onToggleFilter: () -> Void
    let onRefresh: () -> Void

    private var activeChips: [MemoFilterChip] {
        MemoFilterChip.activeChips(for: filter, calendar: .current)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if let errorMessage = viewModel.errorMessage {
                errorBanner(errorMessage)
                Divider()
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if !viewModel.pendingItems.isEmpty {
                        pendingSection
                    }

                    if viewModel.memos.isEmpty && viewModel.pendingItems.isEmpty && !viewModel.isLoading {
                        ContentUnavailableView(mode.emptyTitle, systemImage: mode == .archived ? "archivebox" : "note.text")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 80)
                    } else {
                        sectionTitle

                        ForEach(viewModel.memos) { memo in
                            memoRow(memo)
                        }
                    }

                    if let nextPageToken = viewModel.nextPageToken, !nextPageToken.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding()
                            .onAppear { viewModel.loadMore() }
                    }
                }
                .padding(.vertical, 14)
            }
            .overlay {
                if viewModel.isLoading && viewModel.memos.isEmpty {
                    ProgressView()
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .onAppear {
            viewModel.memos = mode == .normal ? MemoCache.shared.memos : []
            viewModel.pendingItems = mode == .normal ? OfflineQueue.shared.pendingItems : []
            viewModel.collectionMode = mode
            viewModel.externalFilterState = effectiveFilter
        }
        .onReceive(NotificationCenter.default.publisher(for: .memosDidChange)) { _ in
            viewModel.refresh()
        }
        .onChange(of: filter) { _, newValue in
            selectedMemo = nil
            viewModel.externalFilterState = effectiveFilter(from: newValue)
        }
        .onChange(of: viewModel.memos) { _, newMemos in
            syncSelectedMemo(from: newMemos)
            syncTagHistory(from: newMemos)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button(action: onToggleFilter) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help("显示或隐藏过滤栏")

                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.title)
                        .font(.system(size: 22, weight: .bold))

                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if mode.showsCreateButton {
                    Button {
                        QuickMemoPanelController.shared.show()
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .help("新建")
                    .accessibilityLabel("新建")
                }

                if showsRefreshButton {
                    RefreshIconButton(
                        isRefreshing: viewModel.isLoading || isExternalRefreshing,
                        accessibilityLabel: hasResettableFilters ? "重置过滤并同步" : "同步 Memos",
                        help: hasResettableFilters ? "重置过滤并同步" : "同步 Memos",
                        action: onRefresh
                    )
                    .frame(width: 28, height: 28)
                    .disabled(viewModel.isLoading || isExternalRefreshing)
                    .opacity(viewModel.isLoading || isExternalRefreshing ? 0.7 : 1)
                }
            }

            if showsFilterSummary && hasFilterSummary {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(activeChips) { chip in
                            Text(chip.title)
                                .font(.caption)
                                .lineLimit(1)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(.quaternary, in: Capsule())
                        }

                        if showsArchivedSummaryChip {
                            Text(I18n.localized("memos_category_archived", language: appState.language))
                                .font(.caption)
                                .lineLimit(1)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(.quaternary, in: Capsule())
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .frame(minHeight: showsFilterSummary && hasFilterSummary ? 92 : 76)
    }

    private var hasFilterSummary: Bool {
        !activeChips.isEmpty || showsArchivedSummaryChip
    }

    private var hasResettableFilters: Bool {
        !activeChips.isEmpty || showsArchivedSummaryChip
    }

    private var subtitle: String {
        if showsFilterSummary {
            var parts = activeChips.map(\.title)
            if showsArchivedSummaryChip {
                parts.append(I18n.localized("memos_category_archived", language: appState.language))
            }
            if !parts.isEmpty {
                return parts.joined(separator: " · ")
            }
        }

        let count = viewModel.memos.count
        return count == 0 ? "暂无 memo" : "\(count) 个 memo"
    }

    private var sectionTitle: some View {
        Text(mode.sectionTitle)
            .font(.system(size: 24, weight: .bold))
            .padding(.horizontal, 20)
            .padding(.bottom, 2)
    }

    private var pendingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("待同步")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)

            ForEach(viewModel.pendingItems) { item in
                PendingMemoRowView(item: item)
            }
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private func memoRow(_ memo: Memo) -> some View {
        Button {
            selectedMemo = memo
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Text(memo.content.firstLineFallback)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if memo.pinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.orange)
                    }
                }

                HStack(spacing: 6) {
                    Text(memo.createTime, style: .time)
                        .fontWeight(.medium)

                    Text(memo.previewText)
                }
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(1)

                if !memo.tags.isEmpty {
                    HStack(spacing: 5) {
                        ForEach(memo.tags.prefix(3), id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground(for: memo), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(selectedMemo?.name == memo.name ? Color.accentColor.opacity(0.22) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
    }

    private func rowBackground(for memo: Memo) -> Color {
        selectedMemo?.name == memo.name
            ? Color.accentColor.opacity(0.16)
            : Color(NSColor.windowBackgroundColor)
    }

    private var effectiveFilter: MemoFilterState {
        effectiveFilter(from: filter)
    }

    private var showsArchivedSummaryChip: Bool {
        filter.showArchived && mode != .archived
    }

    private func effectiveFilter(from filter: MemoFilterState) -> MemoFilterState {
        var next = filter
        next.showArchived = mode == .archived
        return next
    }

    private func syncSelectedMemo(from memos: [Memo]) {
        guard let selectedMemo else { return }
        guard let refreshedMemo = memos.first(where: { $0.name == selectedMemo.name }) else {
            self.selectedMemo = nil
            return
        }
        self.selectedMemo = refreshedMemo
    }

    private func syncTagHistory(from memos: [Memo]) {
        var tags = appState.memosTagHistory
        var seenTags = Set(tags)
        for memo in memos {
            for tag in memo.tags where !seenTags.contains(tag) {
                tags.append(tag)
                seenTags.insert(tag)
            }
        }
        appState.memosTagHistory = tags.sorted()
    }
}

private extension Memo {
    var previewText: String {
        if let snippet, !snippet.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return snippet
        }

        let lines = content
            .split(whereSeparator: \.isNewline)
            .map(String.init)

        if lines.count > 1 {
            return lines.dropFirst().joined(separator: " ")
        }

        return "无更多文本"
    }
}

private extension String {
    var firstLineFallback: String {
        let firstLine = split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "无标题" : trimmed
    }
}
