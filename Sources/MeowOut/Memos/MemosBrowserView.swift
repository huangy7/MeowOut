import SwiftUI
import MemosKit

struct MemosBrowserView: View {
    var body: some View {
        MemosRootView()
    }
}

struct MemosLegacyBrowserContent: View {
    @Environment(AppState.self) private var appState
    @State private var filter = MemoFilterState()
    @State private var calendarIndex = CalendarMemoIndex(dates: [])
    @State private var isLoadingStats = false

    @State private var editorText = ""
    @State private var selectedTags: Set<String> = []
    @State private var visibility: MemoVisibility = .private

    var body: some View {
        HSplitView {
            MemoCalendarSidebarView(
                filter: $filter,
                calendarIndex: calendarIndex,
                allTags: appState.memosTagHistory,
                treatsArchivedAsBaseState: false,
                isRefreshing: isLoadingStats,
                onRefresh: {
                    filter.reset()
                    NotificationCenter.default.post(name: .memosDidChange, object: nil)
                }
            )
            .frame(minWidth: 240, maxWidth: 300)

            VStack(spacing: 0) {
                MemoEditorView(
                    text: $editorText,
                    selectedTags: $selectedTags,
                    visibility: $visibility,
                    availableTags: appState.memosTagHistory,
                    placeholder: I18n.localized("memos_editor_placeholder", language: appState.language),
                    showsFocusButton: true,
                    onFocus: {
                        QuickMemoPanelController.shared.show()
                    },
                    onSave: {
                        saveMemo()
                    }
                )
                .padding(16)

                Divider()

                MemoTimelineView(
                    allTags: appState.memosTagHistory,
                    externalFilterState: filter
                )
            }
            .frame(minWidth: 600)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .onAppear {
            visibility = MemoVisibility(rawValue: appState.memosDefaultVisibility) ?? .private
            loadStats()
        }
        .onReceive(NotificationCenter.default.publisher(for: .memosDidChange)) { _ in
            loadStats()
        }
    }

    private func saveMemo() {
        let content = editorText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }

        Task {
            do {
                _ = try await MemosClient.shared.createMemo(content: content, visibility: visibility)
                await MainActor.run {
                    editorText = ""
                    selectedTags = []
                    NotificationCenter.default.post(name: .memosDidChange, object: nil)
                }
            } catch {
                QueueProcessor.shared.enqueueAndProcess(.create(content: content, visibility: visibility, attachments: nil, archiveAfterCreate: false))
                await MainActor.run {
                    editorText = ""
                    selectedTags = []
                    NotificationCenter.default.post(name: .memosDidChange, object: nil)
                }
            }
        }
    }

    private func loadStats() {
        guard !isLoadingStats else { return }
        isLoadingStats = true

        Task {
            do {
                let user = try await MemosClient.shared.getCurrentUser()
                let stats = try await MemosClient.shared.getUserStats(userName: user.name)

                await MainActor.run {
                    self.calendarIndex = CalendarMemoIndex(dates: stats.memoCreatedTimestamps)
                    self.appState.memosTagHistory = Array(stats.tagCount.keys).sorted()
                    self.isLoadingStats = false
                }
            } catch {
                print("Failed to load stats: \(error)")
                await MainActor.run {
                    self.isLoadingStats = false
                }
            }
        }
    }
}
