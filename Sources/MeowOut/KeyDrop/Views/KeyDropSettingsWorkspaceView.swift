// Sources/MeowOut/KeyDrop/Views/KeyDropSettingsWorkspaceView.swift
import SwiftUI
import KeyboardShortcuts

/// 设置内「常用语」主工作台：统一 14pt 留白浅灰画布，顶部浮起白色配置条（避免 macOS 26 Toolbar 破坏快捷键控件），
/// 下方左右双栏无全宽分割线割裂，顶底齐平。
struct KeyDropSettingsWorkspaceView: View {
    private enum PendingDraftInterruption {
        case selectSnippet(UUID)
        case selectCategory(String)
        case startNewDraft
    }

    @Environment(AppState.self) private var appState
    @ObservedObject var store = SnippetStore.shared
    @Bindable var browse: KeyDropBrowseState

    let keyDropEnabledBinding: Binding<Bool>

    @State private var activeDraft: SnippetDraft? = nil
    @State private var pendingDraftInterruption: PendingDraftInterruption? = nil
    @State private var snippetPendingDelete: Snippet? = nil
    @State private var draggedSnippet: Snippet? = nil

    private var filteredSnippets: [Snippet] {
        browse.filteredSnippets(from: store.snippets)
    }

    private var selectedSnippet: Snippet? {
        guard let id = browse.selectedSnippetID else { return nil }
        return filteredSnippets.first(where: { $0.id == id })
    }

    var body: some View {
        VStack(spacing: 12) {
            floatingConfigCard

            HStack(alignment: .top, spacing: 14) {
                SnippetListColumnView(
                    store: store,
                    snippets: filteredSnippets,
                    totalSnippetCount: store.snippets.count,
                    selectedCategory: browse.selectedCategory,
                    searchText: $browse.searchText,
                    selectedSnippetID: browse.selectedSnippetID,
                    isCreatingDraft: activeDraft != nil,
                    draggedSnippet: $draggedSnippet,
                    onSelectCategory: { category in
                        handleCategorySelectionRequest(category)
                    },
                    onCategoryRenamed: { oldName, newName in
                        if browse.selectedCategory == oldName {
                            browse.selectedCategory = newName
                        }
                        if activeDraft?.category == oldName {
                            activeDraft?.category = newName
                        }
                    },
                    onCategoryDeleted: { deletedCategory in
                        if browse.selectedCategory == deletedCategory {
                            browse.selectedCategory = KeyDropConstants.categoryAll
                        }
                        if activeDraft?.category == deletedCategory {
                            activeDraft?.category = KeyDropConstants.categoryUncategorized
                        }
                        reconcileBrowseState()
                    },
                    onSelectSnippet: { id in
                        handleSnippetSelectionRequest(id)
                    },
                    onRequestDelete: { snippet in
                        snippetPendingDelete = snippet
                    },
                    onMoveSnippetToCategory: { snippet, targetCategory in
                        moveSnippet(snippet, to: targetCategory)
                    },
                    onStartNewSnippet: {
                        startNewDraft()
                    },
                    onClearSearch: {
                        browse.searchText = ""
                    }
                )
                .frame(width: 256)

                rightDetailPane
                    .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            reconcileBrowseState()
        }
        .onChange(of: browse.selectedCategory) { _, _ in
            reconcileBrowseState()
        }
        .onChange(of: browse.searchText) { _, _ in
            reconcileBrowseState()
        }
        .onChange(of: store.snippets) { _, _ in
            reconcileBrowseState()
        }
        .onChange(of: store.customCategories) { _, _ in
            reconcileBrowseState()
        }
        .alert(
            I18n.localized("keydrop_delete_snippet_confirm_title", language: appState.language),
            isPresented: Binding(
                get: { snippetPendingDelete != nil },
                set: { if !$0 { snippetPendingDelete = nil } }
            )
        ) {
            if let snippet = snippetPendingDelete {
                Button(I18n.localized("keydrop_delete_snippet", language: appState.language), role: .destructive) {
                    confirmDelete(snippet)
                }
                Button(I18n.localized("keydrop_cancel_btn", language: appState.language), role: .cancel) {
                    snippetPendingDelete = nil
                }
            }
        } message: {
            if let snippet = snippetPendingDelete {
                let name = snippet.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? I18n.localized("keydrop_default_title", language: appState.language)
                    : snippet.title
                Text(I18n.localizedFormat("keydrop_delete_snippet_confirm_message", language: appState.language, name))
            }
        }
        .alert(
            I18n.localized("keydrop_discard_draft_title", language: appState.language),
            isPresented: Binding(
                get: { pendingDraftInterruption != nil },
                set: { if !$0 { pendingDraftInterruption = nil } }
            )
        ) {
            Button(I18n.localized("keydrop_discard_draft_btn", language: appState.language), role: .destructive) {
                let pending = pendingDraftInterruption
                pendingDraftInterruption = nil
                activeDraft = nil
                if let pending {
                    applyDraftInterruption(pending)
                }
            }
            Button(I18n.localized("keydrop_keep_editing_btn", language: appState.language), role: .cancel) {
                pendingDraftInterruption = nil
            }
        } message: {
            Text(I18n.localized("keydrop_discard_draft_message", language: appState.language))
        }
    }

    // MARK: - 顶部悬浮配置卡（与 SettingsGroup 同款白卡材质，避免 Toolbar 破坏快捷键控件）

    private var floatingConfigCard: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Text(I18n.localized("keydrop_enabled", language: appState.language))
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                Toggle("", isOn: keyDropEnabledBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                Text(I18n.localized("keydrop_shortcut_compact", language: appState.language))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                ShortcutRecorderView(for: .togglePanel)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.02), radius: 2, x: 0, y: 1)
    }

    // MARK: - 右侧详情区

    @ViewBuilder
    private var rightDetailPane: some View {
        if activeDraft != nil {
            SnippetDraftEditorView(
                store: store,
                draft: Binding(
                    get: { activeDraft ?? SnippetDraft() },
                    set: { activeDraft = $0 }
                ),
                onCancel: {
                    activeDraft = nil
                    reconcileBrowseState()
                },
                onCommit: {
                    commitActiveDraft()
                }
            )
            .id(activeDraft?.sessionID)
        } else if let snippet = selectedSnippet {
            SnippetExistingEditorView(
                store: store,
                snippet: snippet,
                onCategoryChangedInEditor: { newCategory in
                    if browse.selectedCategory != KeyDropConstants.categoryAll,
                       browse.selectedCategory != newCategory {
                        browse.selectedCategory = newCategory
                    }
                    browse.selectedSnippetID = snippet.id
                },
                onRequestDelete: { target in
                    snippetPendingDelete = target
                }
            )
            .id(snippet.id)
        } else {
            emptyDetailGuide
        }
    }

    private var emptyDetailGuide: some View {
        SnippetEditorCardSurface {
            VStack(spacing: 12) {
                Image(systemName: detailEmptyIcon)
                    .font(.system(size: 30))
                    .foregroundStyle(.tertiary)

                Text(detailEmptyTitle)
                    .font(.system(size: 14, weight: .semibold))

                Text(detailEmptyDescription)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)

                if !browse.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button(I18n.localized("keydrop_clear_search_btn", language: appState.language)) {
                        browse.searchText = ""
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 4)
                } else if store.snippets.isEmpty {
                    Button(I18n.localized("keydrop_create_first_btn", language: appState.language)) {
                        startNewDraft()
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
                } else if filteredSnippets.isEmpty {
                    Button(I18n.localized("keydrop_create_in_category_btn", language: appState.language)) {
                        startNewDraft()
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var detailEmptyIcon: String {
        if !browse.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "magnifyingglass"
        }
        if store.snippets.isEmpty {
            return "keyboard"
        }
        if filteredSnippets.isEmpty {
            return "folder"
        }
        return "sidebar.left"
    }

    private var detailEmptyTitle: String {
        if !browse.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return I18n.localized("keydrop_panel_no_matches", language: appState.language)
        }
        if store.snippets.isEmpty {
            return I18n.localized("keydrop_empty_library_title", language: appState.language)
        }
        if filteredSnippets.isEmpty {
            return I18n.localized("keydrop_empty_category_title", language: appState.language)
        }
        return I18n.localized("keydrop_select_prompt_title", language: appState.language)
    }

    private var detailEmptyDescription: String {
        if !browse.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return I18n.localized("keydrop_search_full_placeholder", language: appState.language)
        }
        if store.snippets.isEmpty {
            return I18n.localized("keydrop_empty_library_desc", language: appState.language)
        }
        if filteredSnippets.isEmpty {
            return I18n.localized("keydrop_empty_category_desc", language: appState.language)
        }
        return I18n.localized("keydrop_select_prompt_desc", language: appState.language)
    }

    // MARK: - 协调动作

    private func startNewDraft() {
        if let existingDraft = activeDraft {
            if existingDraft.hasUnsavedInput {
                pendingDraftInterruption = .startNewDraft
            }
            return
        }
        createFreshDraft()
    }

    private func createFreshDraft() {
        let defaultCategory = browse.selectedCategory == KeyDropConstants.categoryAll
            ? KeyDropConstants.categoryUncategorized
            : browse.selectedCategory
        activeDraft = SnippetDraft(category: defaultCategory)
    }

    private func commitActiveDraft() {
        guard let draft = activeDraft, draft.canSave else { return }
        let created = draft.makeSnippet()
        store.add(snippet: created)
        activeDraft = nil

        if !browse.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let query = browse.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesSearch = created.title.localizedCaseInsensitiveContains(query) ||
                created.content.localizedCaseInsensitiveContains(query)
            if !matchesSearch {
                browse.searchText = ""
            }
        }

        if browse.selectedCategory != KeyDropConstants.categoryAll,
           browse.selectedCategory != created.category {
            browse.selectedCategory = created.category
        }
        browse.selectedSnippetID = created.id
    }

    private func handleSnippetSelectionRequest(_ id: UUID) {
        if let draft = activeDraft {
            if draft.hasUnsavedInput {
                pendingDraftInterruption = .selectSnippet(id)
                return
            }
            activeDraft = nil
        }
        browse.selectedSnippetID = id
    }

    private func handleCategorySelectionRequest(_ category: String) {
        if let draft = activeDraft {
            if draft.hasUnsavedInput {
                pendingDraftInterruption = .selectCategory(category)
                return
            }
            activeDraft = nil
        }
        browse.selectedCategory = category
    }

    private func applyDraftInterruption(_ action: PendingDraftInterruption) {
        switch action {
        case .selectSnippet(let id):
            browse.selectedSnippetID = id
        case .selectCategory(let category):
            browse.selectedCategory = category
        case .startNewDraft:
            createFreshDraft()
        }
    }

    private func moveSnippet(_ snippet: Snippet, to targetCategory: String) {
        var updated = snippet
        updated.category = targetCategory
        store.update(snippet: updated)
        reconcileBrowseState()
    }

    private func confirmDelete(_ snippet: Snippet) {
        let nextSelection = KeyDropBrowseState.selectionAfterDeleting(id: snippet.id, in: filteredSnippets)
        store.delete(snippet: snippet)
        snippetPendingDelete = nil
        browse.selectedSnippetID = nextSelection
        reconcileBrowseState()
    }

    private func reconcileBrowseState() {
        if browse.selectedCategory == KeyDropConstants.categoryUncategorized,
           store.snippetCount(in: KeyDropConstants.categoryUncategorized) == 0 {
            browse.selectedCategory = KeyDropConstants.categoryAll
        }
        if !store.managerCategories.contains(browse.selectedCategory) {
            browse.selectedCategory = KeyDropConstants.categoryAll
        }
        if activeDraft == nil {
            browse.selectedSnippetID = KeyDropBrowseState.reconciledSelection(
                currentID: browse.selectedSnippetID,
                in: filteredSnippets
            )
        }
    }
}
