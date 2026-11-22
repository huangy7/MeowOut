// Sources/MeowOut/KeyDrop/Views/SnippetListColumnView.swift
import SwiftUI
import UniformTypeIdentifiers

/// 左栏词条列表：搜索与新建 + 流式分类标签 + 浮动白色卡片列表，底部不再堆叠多余统计栏。
struct SnippetListColumnView: View {
    @Environment(AppState.self) private var appState
    @ObservedObject var store: SnippetStore

    let snippets: [Snippet]
    let totalSnippetCount: Int
    let selectedCategory: String
    @Binding var searchText: String
    let selectedSnippetID: UUID?
    let isCreatingDraft: Bool
    @Binding var draggedSnippet: Snippet?

    let onSelectCategory: (String) -> Void
    let onCategoryRenamed: (String, String) -> Void
    let onCategoryDeleted: (String) -> Void
    let onSelectSnippet: (UUID) -> Void
    let onRequestDelete: (Snippet) -> Void
    let onMoveSnippetToCategory: (Snippet, String) -> Void
    let onStartNewSnippet: () -> Void
    let onClearSearch: () -> Void

    @FocusState private var isSearchFocused: Bool
    @FocusState private var isListFocused: Bool
    @State private var isHoveringAddButton = false

    private var hasSearchQuery: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 10) {
            searchHeader

            SnippetCategoryBarView(
                store: store,
                selectedCategory: selectedCategory,
                draggedSnippet: $draggedSnippet,
                onSelectCategory: onSelectCategory,
                onCategoryRenamed: onCategoryRenamed,
                onCategoryDeleted: onCategoryDeleted
            )

            listBody
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: - 搜索与新建顶栏

    private var searchHeader: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 11.5))

                TextField(
                    I18n.localized("keydrop_search_full_placeholder", language: appState.language),
                    text: $searchText
                )
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($isSearchFocused)

                if hasSearchQuery {
                    Text("\(snippets.count)/\(totalSnippetCount)")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 11.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(I18n.localized("keydrop_clear_search_btn", language: appState.language))
                } else if !isSearchFocused {
                    Text("⌘F")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.primary.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isSearchFocused ? Color.accentColor.opacity(0.65) : Color.primary.opacity(0.08),
                        lineWidth: 1
                    )
            )

            // 隐形快捷键代理：Cmd+F 聚焦搜索框
            Button("") {
                isSearchFocused = true
            }
            .keyboardShortcut("f", modifiers: .command)
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)

            Button {
                onStartNewSnippet()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isHoveringAddButton ? Color.accentColor : Color.primary.opacity(0.78))
                    .frame(width: 28, height: 28)
                    .background(
                        isHoveringAddButton
                            ? Color.accentColor.opacity(0.1)
                            : Color(nsColor: .controlBackgroundColor)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(
                                isHoveringAddButton ? Color.accentColor.opacity(0.4) : Color.primary.opacity(0.08),
                                lineWidth: 1
                            )
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("n", modifiers: .command)
            .help("\(I18n.localized("keydrop_new_snippet_btn", language: appState.language)) (⌘N)")
            .accessibilityLabel(I18n.localized("keydrop_new_snippet_btn", language: appState.language))
            .onHover { hovering in
                isHoveringAddButton = hovering
            }
        }
    }

    // MARK: - 卡片列表

    @ViewBuilder
    private var listBody: some View {
        if snippets.isEmpty && !isCreatingDraft {
            emptyListPlaceholder
        } else {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 8) {
                        if isCreatingDraft {
                            draftIndicatorCard
                                .id("draft-indicator-row")
                        }

                        ForEach(snippets) { snippet in
                            SnippetCardRowView(
                                snippet: snippet,
                                isSelected: !isCreatingDraft && selectedSnippetID == snippet.id,
                                showCategoryBadge: selectedCategory == KeyDropConstants.categoryAll,
                                moveTargetCategories: store.editableCategories.filter { $0 != snippet.category },
                                language: appState.language,
                                onSelect: {
                                    isListFocused = true
                                    onSelectSnippet(snippet.id)
                                },
                                onRequestDelete: {
                                    onRequestDelete(snippet)
                                },
                                onMoveToCategory: { targetCategory in
                                    onMoveSnippetToCategory(snippet, targetCategory)
                                }
                            )
                            .id(snippet.id)
                            .onDrag {
                                draggedSnippet = snippet
                                return NSItemProvider(object: snippet.id.uuidString as NSString)
                            }
                            .onDrop(of: [UTType.text], delegate: SnippetDropDelegate(
                                item: snippet,
                                items: snippets,
                                draggedItem: $draggedSnippet,
                                searchText: searchText,
                                store: store
                            ))
                        }
                    }
                    .padding(.vertical, 1)
                }
                .focusable()
                .focusEffectDisabled()
                .focused($isListFocused)
                .onKeyPress(.upArrow) {
                    guard !isCreatingDraft,
                          let targetID = KeyDropBrowseState.movedSelection(
                            currentID: selectedSnippetID,
                            delta: -1,
                            in: snippets
                          ) else {
                        return .ignored
                    }
                    onSelectSnippet(targetID)
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(targetID, anchor: .center)
                    }
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    guard !isCreatingDraft,
                          let targetID = KeyDropBrowseState.movedSelection(
                            currentID: selectedSnippetID,
                            delta: 1,
                            in: snippets
                          ) else {
                        return .ignored
                    }
                    onSelectSnippet(targetID)
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(targetID, anchor: .center)
                    }
                    return .handled
                }
                .onChange(of: selectedSnippetID) { _, newID in
                    guard let newID, !isCreatingDraft else { return }
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(newID)
                    }
                }
                .onChange(of: isCreatingDraft) { _, creating in
                    if creating {
                        withAnimation(.easeOut(duration: 0.12)) {
                            proxy.scrollTo("draft-indicator-row", anchor: .top)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 草稿卡片与空态

    private var draftIndicatorCard: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(I18n.localized("keydrop_draft_row_title", language: appState.language))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text(I18n.localized("keydrop_draft_row_badge", language: appState.language))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }

            Text(I18n.localized("keydrop_draft_row_subtitle", language: appState.language))
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    Color.accentColor.opacity(0.5),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                )
        )
    }

    private var emptyListPlaceholder: some View {
        VStack(spacing: 10) {
            Image(systemName: emptyIconName)
                .font(.system(size: 22))
                .foregroundStyle(.tertiary)

            Text(emptyTitle)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if hasSearchQuery {
                Button(I18n.localized("keydrop_clear_search_btn", language: appState.language)) {
                    onClearSearch()
                }
                .controlSize(.small)
            } else {
                Button(
                    I18n.localized(
                        selectedCategory == KeyDropConstants.categoryAll
                            ? "keydrop_new_snippet_btn"
                            : "keydrop_create_in_category_btn",
                        language: appState.language
                    )
                ) {
                    onStartNewSnippet()
                }
                .controlSize(.small)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyIconName: String {
        if hasSearchQuery {
            return "magnifyingglass"
        }
        if selectedCategory != KeyDropConstants.categoryAll {
            return "folder"
        }
        return "keyboard"
    }

    private var emptyTitle: String {
        if hasSearchQuery {
            return I18n.localized("keydrop_panel_no_matches", language: appState.language)
        }
        if selectedCategory != KeyDropConstants.categoryAll {
            return I18n.localized("keydrop_empty_category_title", language: appState.language)
        }
        return I18n.localized("keydrop_empty_library_title", language: appState.language)
    }
}

private struct SnippetCardRowView: View {
    let snippet: Snippet
    let isSelected: Bool
    let showCategoryBadge: Bool
    let moveTargetCategories: [String]
    let language: AppState.AppLanguage

    let onSelect: () -> Void
    let onRequestDelete: () -> Void
    let onMoveToCategory: (String) -> Void

    @State private var isHovering = false

    private var singleLinePreview: String {
        let collapsed = snippet.content
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        return collapsed.isEmpty
            ? I18n.localized("keydrop_default_content", language: language)
            : collapsed
    }

    private var displayTitle: String {
        snippet.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? I18n.localized("keydrop_default_title", language: language)
            : snippet.title
    }

    private var charCountLabel: String {
        I18n.localizedFormat("keydrop_chars_count", language: language, snippet.content.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                Text(displayTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                if showCategoryBadge {
                    categoryBadge
                }
            }

            HStack(alignment: .center, spacing: 8) {
                Text(singleLinePreview)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text(charCountLabel)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                Color(nsColor: .controlBackgroundColor)
                if isSelected {
                    Color.accentColor.opacity(0.08)
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(borderColor, lineWidth: isSelected ? 1.25 : 1)
        )
        .shadow(color: Color.black.opacity(isSelected ? 0.04 : 0.02), radius: 2, x: 0, y: 1)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
        .contextMenu {
            if !moveTargetCategories.isEmpty {
                Menu(I18n.localized("keydrop_move_to_category", language: language)) {
                    ForEach(moveTargetCategories, id: \.self) { target in
                        Button(categoryDisplayName(target)) {
                            onMoveToCategory(target)
                        }
                    }
                }
                Divider()
            }

            Button(I18n.localized("keydrop_delete_snippet", language: language), role: .destructive) {
                onRequestDelete()
            }
        }
    }

    private var categoryBadge: some View {
        let tint = SnippetCategoryStyle.tint(for: snippet.category)
        return Text(categoryDisplayName(snippet.category))
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(tint ?? Color.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint?.opacity(0.12) ?? Color.primary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .lineLimit(1)
    }

    private var borderColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.55)
        }
        if isHovering {
            return Color.primary.opacity(0.14)
        }
        return Color.primary.opacity(0.06)
    }

    private func categoryDisplayName(_ category: String) -> String {
        if category == KeyDropConstants.categoryUncategorized || category.isEmpty {
            return I18n.localized("keydrop_uncategorized", language: language)
        }
        return category
    }
}
