// Sources/MeowOut/KeyDrop/Views/SnippetCategoryBarView.swift
import SwiftUI
import UniformTypeIdentifiers

/// 列表栏内的流式分类标签区：柔和浅色选中态、右键重命名/合并/删除、以及拖拽词条归类落点。
struct SnippetCategoryBarView: View {
    @Environment(AppState.self) private var appState
    @ObservedObject var store: SnippetStore

    let selectedCategory: String
    @Binding var draggedSnippet: Snippet?
    let onSelectCategory: (String) -> Void
    let onCategoryRenamed: (String, String) -> Void
    let onCategoryDeleted: (String) -> Void

    @State private var targetedCategory: String? = nil

    // 分类新建 / 重命名 / 合并 / 删除确认弹窗状态
    @State private var showingAddCategoryAlert = false
    @State private var newCategoryNameInput = ""

    @State private var showingRenameCategoryAlert = false
    @State private var showingMergeWarningAlert = false
    @State private var categoryToRename = ""
    @State private var newCategoryNameForRename = ""

    @State private var categoryPendingDelete: String? = nil

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(store.managerCategories, id: \.self) { category in
                categoryChip(for: category)
            }

            Button {
                newCategoryNameInput = ""
                showingAddCategoryAlert = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(I18n.localized("keydrop_add_category_btn", language: appState.language))
            .accessibilityLabel(I18n.localized("keydrop_add_category_btn", language: appState.language))
        }
        .alert(
            I18n.localized("keydrop_add_category_title", language: appState.language),
            isPresented: $showingAddCategoryAlert
        ) {
            TextField(
                I18n.localized("keydrop_add_category_placeholder", language: appState.language),
                text: $newCategoryNameInput
            )
            Button(I18n.localized("keydrop_save_btn", language: appState.language)) {
                confirmAddCategory()
            }
            Button(I18n.localized("keydrop_cancel_btn", language: appState.language), role: .cancel) {
                newCategoryNameInput = ""
            }
        } message: {
            Text(I18n.localized("keydrop_add_category_prompt", language: appState.language))
        }
        .alert(
            I18n.localized("keydrop_rename_category", language: appState.language),
            isPresented: $showingRenameCategoryAlert
        ) {
            TextField(
                I18n.localized("keydrop_add_category_placeholder", language: appState.language),
                text: $newCategoryNameForRename
            )
            Button(I18n.localized("keydrop_save_btn", language: appState.language)) {
                confirmRenameCategory()
            }
            Button(I18n.localized("keydrop_cancel_btn", language: appState.language), role: .cancel) {
                newCategoryNameForRename = ""
            }
        } message: {
            Text(I18n.localized("keydrop_rename_category_prompt", language: appState.language))
        }
        .alert(
            I18n.localized("keydrop_merge_warning_title", language: appState.language),
            isPresented: $showingMergeWarningAlert
        ) {
            Button(I18n.localized("keydrop_merge_btn", language: appState.language), role: .destructive) {
                let trimmed = newCategoryNameForRename.trimmingCharacters(in: .whitespacesAndNewlines)
                store.renameCategory(oldName: categoryToRename, newName: trimmed)
                onCategoryRenamed(categoryToRename, trimmed)
                newCategoryNameForRename = ""
            }
            Button(I18n.localized("keydrop_cancel_btn", language: appState.language), role: .cancel) {
                newCategoryNameForRename = ""
            }
        } message: {
            Text(I18n.localized("keydrop_merge_warning_message", language: appState.language))
        }
        .confirmationDialog(
            categoryPendingDelete.map {
                I18n.localizedFormat("keydrop_delete_category_title", language: appState.language, $0)
            } ?? "",
            isPresented: Binding(
                get: { categoryPendingDelete != nil },
                set: { if !$0 { categoryPendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let cat = categoryPendingDelete {
                let count = store.snippetCount(in: cat)
                Button(I18n.localized("keydrop_delete_category_keep_snippets", language: appState.language)) {
                    store.deleteCategory(name: cat, deleteSnippets: false)
                    onCategoryDeleted(cat)
                    categoryPendingDelete = nil
                }
                Button(
                    I18n.localizedFormat("keydrop_delete_category_with_snippets", language: appState.language, count),
                    role: .destructive
                ) {
                    store.deleteCategory(name: cat, deleteSnippets: true)
                    onCategoryDeleted(cat)
                    categoryPendingDelete = nil
                }
                Button(I18n.localized("keydrop_cancel_btn", language: appState.language), role: .cancel) {
                    categoryPendingDelete = nil
                }
            }
        } message: {
            if let cat = categoryPendingDelete {
                let count = store.snippetCount(in: cat)
                Text(I18n.localizedFormat("keydrop_delete_category_message", language: appState.language, count))
            }
        }
    }

    private func categoryChip(for category: String) -> some View {
        let isSelected = selectedCategory == category
        let isTargeted = targetedCategory == category
        let count = store.snippetCount(in: category)
        let accent = SnippetCategoryStyle.tint(for: category) ?? Color.accentColor

        return Button {
            onSelectCategory(category)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: SnippetCategoryStyle.iconName(for: category))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isSelected ? accent : (SnippetCategoryStyle.tint(for: category) ?? .secondary))

                Text(displayName(for: category))
                    .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? accent : .primary)
                    .lineLimit(1)

                Text("\(count)")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(isSelected ? accent.opacity(0.85) : .secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Group {
                    if isTargeted {
                        Color.accentColor.opacity(0.2)
                    } else if isSelected {
                        accent.opacity(0.13)
                    } else {
                        Color(nsColor: .controlBackgroundColor).opacity(0.9)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(
                        isTargeted
                            ? Color.accentColor
                            : (isSelected ? accent.opacity(0.32) : Color.primary.opacity(0.07)),
                        lineWidth: isTargeted ? 1.5 : 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if category != KeyDropConstants.categoryAll {
                Button(I18n.localized("keydrop_rename_category", language: appState.language)) {
                    categoryToRename = category
                    newCategoryNameForRename = category == KeyDropConstants.categoryUncategorized ? "" : category
                    showingRenameCategoryAlert = true
                }
            }
            if category != KeyDropConstants.categoryAll && category != KeyDropConstants.categoryUncategorized {
                Divider()
                Button(I18n.localized("keydrop_delete_category", language: appState.language), role: .destructive) {
                    requestDeleteCategory(category)
                }
            }
        }
        .onDrop(of: [UTType.text], delegate: CategoryDropDelegate(
            targetCategory: category,
            draggedItem: $draggedSnippet,
            targetedCategory: $targetedCategory,
            store: store
        ))
    }

    private func confirmAddCategory() {
        let input = newCategoryNameInput
        newCategoryNameInput = ""
        if let created = store.addCategory(input) {
            onSelectCategory(created)
        }
    }

    private func confirmRenameCategory() {
        let trimmed = newCategoryNameForRename.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed != categoryToRename,
              trimmed != KeyDropConstants.categoryAll,
              trimmed != KeyDropConstants.categoryUncategorized else {
            return
        }

        let existingCustomCategories = store.managerCategories.filter {
            $0 != KeyDropConstants.categoryAll && $0 != KeyDropConstants.categoryUncategorized
        }
        if existingCustomCategories.contains(trimmed) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                showingMergeWarningAlert = true
            }
        } else {
            store.renameCategory(oldName: categoryToRename, newName: trimmed)
            onCategoryRenamed(categoryToRename, trimmed)
            newCategoryNameForRename = ""
        }
    }

    private func requestDeleteCategory(_ category: String) {
        if store.snippetCount(in: category) == 0 {
            store.deleteCategory(name: category, deleteSnippets: false)
            onCategoryDeleted(category)
        } else {
            categoryPendingDelete = category
        }
    }

    private func displayName(for category: String) -> String {
        if category == KeyDropConstants.categoryAll {
            return I18n.localized("keydrop_category_all", language: appState.language)
        }
        if category == KeyDropConstants.categoryUncategorized {
            return I18n.localized("keydrop_uncategorized", language: appState.language)
        }
        return category
    }
}
