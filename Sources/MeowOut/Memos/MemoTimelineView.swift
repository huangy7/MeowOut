import SwiftUI
import MemosKit

@MainActor
@Observable
class MemoTimelineViewModel {
    var memos: [Memo] = []
    var pendingItems: [OfflineQueue.QueueItem] = []
    var isLoading = false
    var searchText = ""
    var selectedTag: String? = nil
    var selectedDate: Date? = nil
    var showArchived = false
    var nextPageToken: String? = nil
    var editingMemoName: String? = nil
    var editingContent: String = ""
    var errorMessage: String? = nil
    var collectionMode: MemosCollectionMode = .normal

    var externalFilterState: MemoFilterState? {
        didSet {
            if let filter = externalFilterState {
                searchText = filter.searchText
                selectedTag = filter.selectedTag
                selectedDate = filter.selectedDate
                showArchived = collectionMode == .archived || filter.showArchived
                refresh()
            }
        }
    }

    private let client = MemosClient.shared
    private let cache = MemoCache.shared
    private let queue = OfflineQueue.shared
    private let processor = QueueProcessor.shared
    private var requestGeneration = 0

    func loadInitial() {
        memos = cache.memos
        pendingItems = queue.pendingItems
        if cache.needsRefresh() { refresh() }
    }

    func refresh() {
        guard client.isConfigured else { return }
        requestGeneration += 1
        let generation = requestGeneration
        let filter = buildFilter()
        let state: MemoState = showArchived ? .archived : .normal
        let shouldUpdateCache = !showArchived && filter == nil
        isLoading = true
        Task {
            do {
                let response = try await client.listMemos(state: state, filter: filter, pageSize: 50)
                guard generation == requestGeneration else { return }
                memos = response.memos
                nextPageToken = Self.normalizedPageToken(response.nextPageToken)
                if shouldUpdateCache {
                    cache.save(memos: response.memos)
                }
                errorMessage = nil
            } catch {
                guard generation == requestGeneration else { return }
                errorMessage = error.localizedDescription
            }
            isLoading = false
            pendingItems = queue.pendingItems
        }
    }

    func loadMore() {
        guard let token = nextPageToken, !token.isEmpty, client.isConfigured, !isLoading else { return }
        let generation = requestGeneration
        let filter = buildFilter()
        let state: MemoState = showArchived ? .archived : .normal
        isLoading = true
        Task {
            do {
                let response = try await client.listMemos(state: state, filter: filter, pageSize: 50, pageToken: token)
                guard generation == requestGeneration else { return }
                memos.append(contentsOf: response.memos)
                nextPageToken = Self.normalizedPageToken(response.nextPageToken)
            } catch {
                guard generation == requestGeneration else { return }
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    func archiveMemo(_ memo: Memo) {
        Task {
            do {
                _ = try await client.updateMemo(name: memo.name, state: .archived, updateMask: ["state"])
                refresh()
            } catch {
                processor.enqueueAndProcess(.update(memoName: memo.name, content: nil, state: .archived, attachments: nil, updateMask: ["state"]))
            }
        }
    }

    func unarchiveMemo(_ memo: Memo) {
        Task {
            do {
                _ = try await client.updateMemo(name: memo.name, state: .normal, updateMask: ["state"])
                refresh()
            } catch {
                processor.enqueueAndProcess(.update(memoName: memo.name, content: nil, state: .normal, attachments: nil, updateMask: ["state"]))
            }
        }
    }

    func togglePin(_ memo: Memo) {
        Task {
            do {
                _ = try await client.updateMemo(name: memo.name, pinned: !memo.pinned, updateMask: ["pinned"])
                refresh()
            } catch {}
        }
    }

    func deleteMemo(_ memo: Memo) {
        Task {
            do {
                try await client.deleteMemo(name: memo.name)
                refresh()
            } catch {
                processor.enqueueAndProcess(.delete(memoName: memo.name))
            }
        }
    }

    func startEditing(_ memo: Memo) {
        editingMemoName = memo.name
        editingContent = memo.content
    }

    func saveEdit() {
        guard let name = editingMemoName else { return }
        editingMemoName = nil
        Task {
            do {
                _ = try await client.updateMemo(name: name, content: editingContent, updateMask: ["content"])
                refresh()
            } catch {
                processor.enqueueAndProcess(.update(memoName: name, content: editingContent, state: nil, attachments: nil, updateMask: ["content"]))
            }
        }
    }

    func cancelEdit() { editingMemoName = nil }

    private func buildFilter() -> String? {
        if let externalFilterState {
            return externalFilterState.celFilter(timeZone: .current)
        }
        
        var parts: [String] = []
        if !searchText.isEmpty { parts.append("content.contains(\"\(searchText)\")") }
        if let tag = selectedTag { parts.append("\"\(tag)\" in tags") }
        return parts.isEmpty ? nil : parts.joined(separator: " && ")
    }

    private static func normalizedPageToken(_ token: String?) -> String? {
        guard let token, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return token
    }
}

struct MemoTimelineView: View {
    @Environment(AppState.self) private var appState
    @State var viewModel = MemoTimelineViewModel()
    let allTags: [String]
    let externalFilterState: MemoFilterState?

    init(allTags: [String], externalFilterState: MemoFilterState? = nil) {
        self.allTags = allTags
        self.externalFilterState = externalFilterState
    }

    var body: some View {
        VStack(spacing: 0) {
            if externalFilterState == nil {
                filterBar
                Divider()
            }
            if let error = viewModel.errorMessage {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            scrollableList
        }
    }

    @ViewBuilder
    private var filterBar: some View {
        HStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                TextField("搜索...", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .onSubmit { viewModel.refresh() }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.08))
            .cornerRadius(8)

            Menu {
                Button(String(localized: "category_all", defaultValue: "全部")) { viewModel.selectedTag = nil; viewModel.refresh() }
                Divider()
                ForEach(allTags, id: \.self) { tag in
                    Button("#\(tag)") { viewModel.selectedTag = tag; viewModel.refresh() }
                }
            } label: {
                Text(viewModel.selectedTag.map { "#\($0)" } ?? "全部 tag")
                    .font(.system(size: 11))
            }

            Picker("", selection: $viewModel.showArchived) {
                Text("活跃").tag(false)
                Text(I18n.localized("memos_category_archived", language: appState.language)).tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 120)
            .onChange(of: viewModel.showArchived) { _, _ in viewModel.refresh() }

            Button(action: { viewModel.refresh() }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isLoading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var scrollableList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.pendingItems) { item in
                    PendingMemoRowView(item: item)
                    Divider().padding(.leading, 12)
                }

                if !viewModel.pendingItems.isEmpty && !viewModel.memos.isEmpty {
                    Text("── 以下已同步 ──")
                        .font(.system(size: 10))
                        .foregroundStyle(.quaternary)
                        .padding(.vertical, 6)
                }

                ForEach(viewModel.memos) { memo in
                    if viewModel.editingMemoName == memo.name {
                        VStack(spacing: 4) {
                            TextEditor(text: $viewModel.editingContent)
                                .font(.system(size: 12))
                                .frame(minHeight: 50, maxHeight: 100)
                                .padding(4)
                                .background(Color.accentColor.opacity(0.05))
                                .cornerRadius(6)
                            HStack {
                                Spacer()
                                Button(I18n.localized("memos_action_cancel", language: appState.language)) { viewModel.cancelEdit() }
                                    .font(.system(size: 11))
                                Button(I18n.localized("memos_action_save", language: appState.language)) { viewModel.saveEdit() }
                                    .font(.system(size: 11))
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    } else {
                        MemoRowView(
                            memo: memo,
                            onArchive: { viewModel.archiveMemo(memo) },
                            onUnarchive: { viewModel.unarchiveMemo(memo) },
                            onTogglePin: { viewModel.togglePin(memo) },
                            onDelete: { viewModel.deleteMemo(memo) },
                            onEdit: { viewModel.startEditing(memo) }
                        )
                        .onTapGesture { viewModel.startEditing(memo) }
                    }
                    Divider().padding(.leading, 12)
                }

                if let nextPageToken = viewModel.nextPageToken, !nextPageToken.isEmpty {
                    ProgressView()
                        .padding()
                        .onAppear { viewModel.loadMore() }
                }
            }
        }
        .onAppear {
            viewModel.externalFilterState = externalFilterState
            viewModel.loadInitial()
        }
        .onChange(of: externalFilterState) { _, newValue in
            viewModel.externalFilterState = newValue
        }
        .onChange(of: viewModel.memos) { _, newMemos in
            var tags = Set(appState.memosTagHistory)
            for memo in newMemos { tags.formUnion(memo.tags) }
            appState.memosTagHistory = Array(tags).sorted()
        }
    }
}
