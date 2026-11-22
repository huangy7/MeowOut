// Sources/MeowOut/KeyDrop/Views/SnippetDetailEditorView.swift
import SwiftUI

/// 右侧已有词条编辑卡片：包裹在白色圆角卡片内，字段按「标题 -> 分类 -> 内容 -> 词条信息」自上而下排布。
struct SnippetExistingEditorView: View {
    @Environment(AppState.self) private var appState
    @ObservedObject var store: SnippetStore

    let snippet: Snippet
    let onCategoryChangedInEditor: (String) -> Void
    let onRequestDelete: (Snippet) -> Void

    @State private var title: String
    @State private var content: String
    @State private var category: String
    @State private var savedRecently = false
    @FocusState private var focusedField: SnippetEditorFocusField?

    init(
        store: SnippetStore,
        snippet: Snippet,
        onCategoryChangedInEditor: @escaping (String) -> Void,
        onRequestDelete: @escaping (Snippet) -> Void
    ) {
        self.store = store
        self.snippet = snippet
        self.onCategoryChangedInEditor = onCategoryChangedInEditor
        self.onRequestDelete = onRequestDelete
        _title = State(initialValue: snippet.title)
        _content = State(initialValue: snippet.content)
        _category = State(initialValue: snippet.category.isEmpty ? KeyDropConstants.categoryUncategorized : snippet.category)
    }

    private var hasMetadata: Bool {
        snippet.createdAt != nil || snippet.updatedAt != nil
    }

    var body: some View {
        SnippetEditorCardSurface {
            VStack(alignment: .leading, spacing: 16) {
                SnippetEditorFormFields(
                    store: store,
                    title: $title,
                    content: $content,
                    category: $category,
                    titlePlaceholder: I18n.localized("keydrop_title_placeholder", language: appState.language),
                    focusedField: $focusedField,
                    language: appState.language,
                    onCategoryPicked: { newCategory in
                        save(categoryOverride: newCategory)
                        onCategoryChangedInEditor(newCategory)
                    }
                )

                if hasMetadata {
                    metadataSection
                }

                Divider()

                HStack(spacing: 10) {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 12))
                            .foregroundStyle(.green)
                        Text(I18n.localized("keydrop_autosaved", language: appState.language))
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize()
                        if savedRecently {
                            Text(I18n.localized("keydrop_saved_just_now", language: appState.language))
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .fixedSize()
                        }
                    }

                    Spacer(minLength: 8)

                    Button(role: .destructive) {
                        onRequestDelete(snippet)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "trash")
                                .font(.system(size: 11.5))
                            Text(I18n.localized("keydrop_delete_snippet", language: appState.language))
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                        }
                        .foregroundStyle(Color.red)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.red.opacity(0.2), lineWidth: 1)
                        )
                        .fixedSize()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .onChange(of: title) { _, _ in save() }
        .onChange(of: content) { _, _ in save() }
        .onChange(of: snippet.category) { _, externalCategory in
            let normalized = externalCategory.isEmpty ? KeyDropConstants.categoryUncategorized : externalCategory
            if category != normalized {
                category = normalized
            }
        }
        .onChange(of: snippet.title) { _, externalTitle in
            if title != externalTitle {
                title = externalTitle
            }
        }
        .onChange(of: snippet.content) { _, externalContent in
            if content != externalContent {
                content = externalContent
            }
        }
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(I18n.localized("keydrop_meta_section_title", language: appState.language))
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                if let createdAt = snippet.createdAt {
                    metadataRow(
                        label: I18n.localized("keydrop_meta_created_at", language: appState.language),
                        date: createdAt
                    )
                }
                if let updatedAt = snippet.updatedAt {
                    metadataRow(
                        label: I18n.localized("keydrop_meta_updated_at", language: appState.language),
                        date: updatedAt
                    )
                }
            }
        }
    }

    private func metadataRow(label: String, date: Date) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .frame(width: 56, alignment: .leading)
            Text(Self.timestampFormatter.string(from: date))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    private func save(categoryOverride: String? = nil) {
        guard let original = store.snippets.first(where: { $0.id == snippet.id }) else { return }
        let targetCategory = categoryOverride ?? category
        let normalizedCategory = targetCategory.isEmpty ? KeyDropConstants.categoryUncategorized : targetCategory
        guard original.title != title || original.content != content || original.category != normalizedCategory else {
            return
        }
        var updated = original
        updated.title = title
        updated.content = content
        updated.category = normalizedCategory
        store.update(snippet: updated)
        savedRecently = true
    }
}

/// 右侧新建草稿卡片：仅点击创建才落库，取消直接丢弃无残留。
struct SnippetDraftEditorView: View {
    @Environment(AppState.self) private var appState
    @ObservedObject var store: SnippetStore

    @Binding var draft: SnippetDraft
    let onCancel: () -> Void
    let onCommit: () -> Void

    @FocusState private var focusedField: SnippetEditorFocusField?

    var body: some View {
        SnippetEditorCardSurface {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 11.5, weight: .semibold))
                    Text(I18n.localized("keydrop_draft_banner", language: appState.language))
                        .font(.system(size: 12, weight: .semibold))
                    Spacer(minLength: 8)
                    Text(I18n.localized("keydrop_draft_hint", language: appState.language))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.accentColor.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.24), lineWidth: 1)
                )

                SnippetEditorFormFields(
                    store: store,
                    title: $draft.title,
                    content: $draft.content,
                    category: $draft.category,
                    titlePlaceholder: I18n.localized("keydrop_title_input_placeholder", language: appState.language),
                    focusedField: $focusedField,
                    language: appState.language,
                    onCategoryPicked: { newCategory in
                        draft.category = newCategory
                    }
                )

                Divider()

                HStack(spacing: 10) {
                    Spacer(minLength: 8)

                    Button(I18n.localized("keydrop_cancel_btn", language: appState.language)) {
                        onCancel()
                    }
                    .keyboardShortcut(.escape, modifiers: [])

                    Button(I18n.localized("keydrop_create_btn", language: appState.language)) {
                        onCommit()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!draft.canSave)
                    .keyboardShortcut(.return, modifiers: .command)
                }
            }
        }
        .onAppear {
            DispatchQueue.main.async {
                focusedField = .title
            }
        }
    }
}

/// 右侧统一的白色圆角卡片外壳，与设置页其他 `SettingsGroup` 卡片视觉语言保持一致。
struct SnippetEditorCardSurface<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.025), radius: 3, x: 0, y: 1)
    }
}

private enum SnippetEditorFocusField: Hashable {
    case title
    case content
}

/// 标题、全宽分类下拉与多行内容共用表单区。
private struct SnippetEditorFormFields: View {
    @ObservedObject var store: SnippetStore
    @Binding var title: String
    @Binding var content: String
    @Binding var category: String
    let titlePlaceholder: String
    var focusedField: FocusState<SnippetEditorFocusField?>.Binding
    let language: AppState.AppLanguage
    let onCategoryPicked: (String) -> Void

    private var metrics: SnippetContentMetrics {
        SnippetContentMetrics.measure(content)
    }

    private var contentStatsText: String {
        if metrics.lineCount <= 1 {
            return I18n.localizedFormat("keydrop_chars_count", language: language, metrics.characterCount)
        }
        return I18n.localizedFormat("keydrop_content_stats", language: language, metrics.lineCount, metrics.characterCount)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(I18n.localized("keydrop_title_placeholder", language: language))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.85))

            TextField(titlePlaceholder, text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5, weight: .medium))
                .focused(focusedField, equals: .title)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.028))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            focusedField.wrappedValue == .title
                                ? Color.accentColor.opacity(0.75)
                                : Color.primary.opacity(0.09),
                            lineWidth: focusedField.wrappedValue == .title ? 1.5 : 1
                        )
                )
        }

        VStack(alignment: .leading, spacing: 6) {
            Text(I18n.localized("keydrop_category_label", language: language))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.85))

            SnippetCategoryDropdownField(
                store: store,
                selection: $category,
                language: language,
                onCategoryPicked: onCategoryPicked
            )
        }

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(I18n.localized("keydrop_content_placeholder", language: language))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.85))

                Spacer()

                Text(contentStatsText)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $content)
                    .font(.system(size: 13, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .focused(focusedField, equals: .content)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if content.isEmpty {
                    Text(I18n.localized("keydrop_content_input_placeholder", language: language))
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 10)
                        .allowsHitTesting(false)
                }
            }
            .background(Color.primary.opacity(0.025))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        focusedField.wrappedValue == .content
                            ? Color.accentColor.opacity(0.75)
                            : Color.primary.opacity(0.09),
                        lineWidth: focusedField.wrappedValue == .content ? 1.5 : 1
                    )
            )
            .frame(maxWidth: .infinity, minHeight: 120, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 整宽自定义分类选择器：用 Button + Popover 取代 macOS Menu，确保与标题框同宽同边框，
/// 并支持在弹层内直接输入新建分类（无需二次模态弹窗）。
private struct SnippetCategoryDropdownField: View {
    @ObservedObject var store: SnippetStore
    @Binding var selection: String
    let language: AppState.AppLanguage
    let onCategoryPicked: (String) -> Void

    @State private var isPopoverPresented = false
    @State private var isHoveringTrigger = false
    @State private var hoveredCategory: String? = nil
    @State private var isAddingInlineCategory = false
    @State private var newCategoryInput = ""
    @FocusState private var isNewCategoryFieldFocused: Bool

    private var activeCategory: String {
        store.editableCategories.contains(selection)
            ? selection
            : KeyDropConstants.categoryUncategorized
    }

    var body: some View {
        Button {
            isAddingInlineCategory = false
            newCategoryInput = ""
            isPopoverPresented.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: SnippetCategoryStyle.iconName(for: activeCategory))
                    .font(.system(size: 12))
                    .foregroundStyle(SnippetCategoryStyle.tint(for: activeCategory) ?? .secondary)

                Text(displayName(for: activeCategory))
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(isHoveringTrigger || isPopoverPresented ? 0.045 : 0.028))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isPopoverPresented
                            ? Color.accentColor.opacity(0.75)
                            : Color.primary.opacity(isHoveringTrigger ? 0.15 : 0.09),
                        lineWidth: isPopoverPresented ? 1.5 : 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHoveringTrigger = hovering
        }
        .accessibilityLabel(I18n.localized("keydrop_category_label", language: language))
        .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
            categoryPopoverContent
        }
    }

    private var categoryPopoverContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            if store.editableCategories.count > 8 {
                ScrollView {
                    categoryOptionsList
                }
                .frame(height: 220)
            } else {
                categoryOptionsList
            }

            Divider()
                .padding(.vertical, 2)

            if isAddingInlineCategory {
                HStack(spacing: 6) {
                    TextField(
                        I18n.localized("keydrop_add_category_placeholder", language: language),
                        text: $newCategoryInput
                    )
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .focused($isNewCategoryFieldFocused)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .onSubmit {
                        commitInlineCategory()
                    }

                    Button {
                        commitInlineCategory()
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(canCommitInlineCategory ? Color.accentColor : Color.secondary.opacity(0.35))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canCommitInlineCategory)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .onAppear {
                    DispatchQueue.main.async {
                        isNewCategoryFieldFocused = true
                    }
                }
            } else {
                Button {
                    newCategoryInput = ""
                    isAddingInlineCategory = true
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Color.accentColor)
                        Text(I18n.localized("keydrop_category_new_option", language: language))
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(hoveredCategory == "__NEW__" ? Color.accentColor.opacity(0.1) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    hoveredCategory = hovering ? "__NEW__" : nil
                }
            }
        }
        .padding(8)
        .frame(width: 232)
    }

    private var categoryOptionsList: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(store.editableCategories, id: \.self) { cat in
                categoryOptionRow(cat)
            }
        }
    }

    private func categoryOptionRow(_ cat: String) -> some View {
        let isSelected = cat == activeCategory
        let isHovered = hoveredCategory == cat
        return Button {
            selection = cat
            onCategoryPicked(cat)
            isPopoverPresented = false
        } label: {
            HStack(spacing: 8) {
                Image(systemName: SnippetCategoryStyle.iconName(for: cat))
                    .font(.system(size: 11.5))
                    .foregroundStyle(SnippetCategoryStyle.tint(for: cat) ?? .secondary)
                    .frame(width: 14)

                Text(displayName(for: cat))
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                isHovered
                    ? Color.primary.opacity(0.07)
                    : (isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredCategory = hovering ? cat : (hoveredCategory == cat ? nil : hoveredCategory)
        }
    }

    private var canCommitInlineCategory: Bool {
        let trimmed = newCategoryInput.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty &&
            trimmed != KeyDropConstants.categoryAll &&
            trimmed != KeyDropConstants.categoryUncategorized
    }

    private func commitInlineCategory() {
        guard canCommitInlineCategory else { return }
        if let created = store.addCategory(newCategoryInput) {
            selection = created
            onCategoryPicked(created)
            isAddingInlineCategory = false
            newCategoryInput = ""
            isPopoverPresented = false
        }
    }

    private func displayName(for category: String) -> String {
        if category == KeyDropConstants.categoryUncategorized {
            return I18n.localized("keydrop_uncategorized", language: language)
        }
        return category
    }
}
