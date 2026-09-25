// Sources/MeowOut/KeyDrop/Views/SnippetManagerListView.swift
import SwiftUI
import UniformTypeIdentifiers

/// 常用语列表页。占满设置详情面板宽度；点某一行推进到该条的编辑页。
/// 分类胶囊行与搜索在顶部，列表用原生 List 以获得方向键导航。
struct SnippetManagerListView: View {
    @Environment(AppState.self) private var appState
    @ObservedObject var store = SnippetStore.shared
    @Bindable var browse: KeyDropBrowseState

    /// 打开某条常用语（点击行与新建都走这里，由调用方决定推进到哪个路由）
    let onOpenEntry: (UUID) -> Void

    @State private var selectedRowID: UUID? = nil
    @State private var draggedSnippet: Snippet? = nil
    @State private var targetedCategory: String? = nil

    // 分类的新建 / 重命名 / 合并确认三个 alert 的状态
    @State private var showingAddCategoryAlert = false
    @State private var newCategoryNameInput = ""
    @State private var showingRenameCategoryAlert = false
    @State private var showingMergeWarningAlert = false
    @State private var categoryToRename: String = ""
    @State private var newCategoryNameForRename: String = ""

    private var categories: [String] {
        let list = store.snippets.map { $0.category }
        var unique = Array(Set(list)).filter { !$0.isEmpty && $0 != KeyDropConstants.categoryUncategorized }.sorted()
        if list.contains(KeyDropConstants.categoryUncategorized) {
            unique.append(KeyDropConstants.categoryUncategorized)
        }
        return [KeyDropConstants.categoryAll] + unique
    }

    private var filteredSnippets: [Snippet] {
        let all = store.snippets
        let categoryFiltered = browse.selectedCategory == KeyDropConstants.categoryAll
            ? all
            : all.filter { $0.category == browse.selectedCategory }
        if browse.searchText.isEmpty {
            return categoryFiltered
        }
        return categoryFiltered.filter {
            $0.title.localizedCaseInsensitiveContains(browse.searchText) ||
            $0.content.localizedCaseInsensitiveContains(browse.searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            categoryChipRow

            Divider()

            searchRow

            Divider()

            listContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // 选中态必须在处理函数里就地清掉：List 对已选中的行不会再发 onChange，
        // 若把清空留给视图生命周期（返回时重建），一旦列表在推进过程中没被卸载，
        // 用户返回后再点同一行就毫无反应。就地清空让这条不变量只依赖自身。
        // 置空会再次触发本回调，新值为 nil 时被 guard 挡掉，不会递归推进。
        .onChange(of: selectedRowID) { _, newValue in
            guard let id = newValue else { return }
            selectedRowID = nil
            onOpenEntry(id)
        }
        // 兜底：视图确实重建时也回到无选中状态
        .onAppear { selectedRowID = nil }
    }

    // MARK: - 搜索行

    private var searchRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))
                TextField(I18n.localized("keydrop_search_placeholder", language: appState.language),
                          text: $browse.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))

                if !browse.searchText.isEmpty {
                    Button { browse.searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(I18n.localized("keydrop_cancel_btn", language: appState.language))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.06))
            .cornerRadius(8)

            Button { addNewSnippet() } label: {
                Text(I18n.localized("keydrop_add_btn", language: appState.language))
                    .font(.system(size: 12))
            }
            .help(I18n.localized("keydrop_add_btn", language: appState.language))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - 列表

    @ViewBuilder
    private var listContent: some View {
        if filteredSnippets.isEmpty {
            ContentUnavailableView(
                I18n.localized(store.snippets.isEmpty ? "keydrop_panel_empty" : "keydrop_panel_no_matches",
                               language: appState.language),
                systemImage: "keyboard"
            )
        } else {
            List(selection: $selectedRowID) {
                ForEach(filteredSnippets) { snippet in
                    row(for: snippet)
                }
            }
            .listStyle(.inset)
        }
    }

    private func row(for snippet: Snippet) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(snippet.title.isEmpty
                 ? I18n.localized("keydrop_default_title", language: appState.language)
                 : snippet.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)

            Text(snippet.content.isEmpty
                 ? I18n.localized("keydrop_default_content", language: appState.language)
                 : snippet.content)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .tag(snippet.id)
        .contextMenu {
            Button(I18n.localized("keydrop_delete_snippet", language: appState.language)) {
                delete(snippet)
            }
        }
        .onDrag {
            self.draggedSnippet = snippet
            return NSItemProvider(object: snippet.id.uuidString as NSString)
        }
        .onDrop(of: [UTType.text], delegate: SnippetDropDelegate(
            item: snippet,
            items: filteredSnippets,
            draggedItem: $draggedSnippet,
            searchText: browse.searchText,
            store: store
        ))
    }

    // MARK: - 动作

    private func addNewSnippet() {
        let cat = browse.selectedCategory == KeyDropConstants.categoryAll
            ? KeyDropConstants.categoryUncategorized
            : browse.selectedCategory
        let snippet = Snippet(
            title: I18n.localized("keydrop_default_title", language: appState.language),
            content: I18n.localized("keydrop_default_content", language: appState.language),
            category: cat
        )
        store.add(snippet: snippet)
        onOpenEntry(snippet.id)
    }

    private func delete(_ snippet: Snippet) {
        let wasSelectedCategory = browse.selectedCategory == snippet.category
        store.delete(snippet: snippet)
        // 分类由常用语携带：删掉某分类的最后一条后，该分类就不再出现在胶囊行里。
        // 筛选若继续停在它上面，列表只会给出「无匹配结果」，却没有任何选中的胶囊能解释原因。
        // 只有当这个分类真的被删空时才回落，删掉同类多条中的一条不影响筛选。
        if wasSelectedCategory, !store.snippets.contains(where: { $0.category == snippet.category }) {
            browse.selectedCategory = KeyDropConstants.categoryAll
        }
    }

    // MARK: - 顶部分类胶囊行

    private var categoryChipRow: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(categories, id: \.self) { category in
                        categoryChip(for: category)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }

            Button { showingAddCategoryAlert = true } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(I18n.localized("keydrop_add_category_btn", language: appState.language))
            .accessibilityLabel(I18n.localized("keydrop_add_category_btn", language: appState.language))
            .padding(.trailing, 12)
        }
        .alert(I18n.localized("keydrop_add_category_title", language: appState.language), isPresented: $showingAddCategoryAlert) {
            TextField(I18n.localized("keydrop_add_category_placeholder", language: appState.language), text: $newCategoryNameInput)
            Button(I18n.localized("keydrop_save_btn", language: appState.language)) {
                addNewCategory()
            }
            Button(I18n.localized("keydrop_cancel_btn", language: appState.language), role: .cancel) {
                newCategoryNameInput = ""
            }
        } message: {
            Text(I18n.localized("keydrop_add_category_prompt", language: appState.language))
        }
        .alert(I18n.localized("keydrop_rename_category", language: appState.language), isPresented: $showingRenameCategoryAlert) {
            TextField("", text: $newCategoryNameForRename)
            Button(I18n.localized("keydrop_save_btn", language: appState.language)) {
                let trimmed = newCategoryNameForRename.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, trimmed != categoryToRename, trimmed != KeyDropConstants.categoryAll else { return }

                let allCategories = store.snippets.map { $0.category }
                if allCategories.contains(trimmed) {
                    // 目标名已存在：交给合并确认流程，延迟一拍等当前 alert 收起再弹下一个
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        showingMergeWarningAlert = true
                    }
                } else {
                    store.renameCategory(oldName: categoryToRename, newName: trimmed)
                    if browse.selectedCategory == categoryToRename {
                        browse.selectedCategory = trimmed
                    }
                }
            }
            Button(I18n.localized("keydrop_cancel_btn", language: appState.language), role: .cancel) {
                newCategoryNameForRename = ""
            }
        } message: {
            Text(I18n.localized("keydrop_rename_category_prompt", language: appState.language))
        }
        .alert(I18n.localized("keydrop_merge_warning_title", language: appState.language), isPresented: $showingMergeWarningAlert) {
            Button(I18n.localized("keydrop_merge_btn", language: appState.language), role: .destructive) {
                let trimmed = newCategoryNameForRename.trimmingCharacters(in: .whitespacesAndNewlines)
                store.renameCategory(oldName: categoryToRename, newName: trimmed)
                if browse.selectedCategory == categoryToRename {
                    browse.selectedCategory = trimmed
                }
            }
            Button(I18n.localized("keydrop_cancel_btn", language: appState.language), role: .cancel) {
                newCategoryNameForRename = ""
            }
        } message: {
            Text(I18n.localized("keydrop_merge_warning_message", language: appState.language))
        }
    }

    /// 单个分类胶囊。重命名这类针对分类本身的操作在列表页只有胶囊这一个入口，所以计数徽标与
    /// 右键菜单都长在它上面；它同时是拖拽落点——把常用语拖到某个胶囊上就是改分类的方式，
    /// 落点高亮由 targetedCategory 驱动。
    private func categoryChip(for category: String) -> some View {
        let isSelected = browse.selectedCategory == category
        return Button {
            browse.selectedCategory = category
        } label: {
            HStack(spacing: 6) {
                Image(systemName: iconName(for: category))
                    .font(.system(size: 11))

                Text(displayName(for: category))
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)

                Text("\(countForCategory(category))")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.9) : Color.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(isSelected ? Color.white.opacity(0.2) : Color.primary.opacity(0.06))
                    .cornerRadius(5)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                targetedCategory == category ? Color.accentColor.opacity(0.5) :
                (isSelected ? Color.accentColor : Color.primary.opacity(0.05))
            )
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .contentShape(Rectangle())
            .cornerRadius(7)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if category != KeyDropConstants.categoryAll {
                Button(I18n.localized("keydrop_rename_category", language: appState.language)) {
                    categoryToRename = category
                    // 「未分类」是个哨兵值不是用户起的名字，重命名时留空让用户自己填
                    newCategoryNameForRename = category == KeyDropConstants.categoryUncategorized ? "" : category
                    showingRenameCategoryAlert = true
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

    private func addNewCategory() {
        let trimmed = newCategoryNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // 分类由常用语携带，没有常用语的分类不存在；所以新建分类要落一条占位条目
        let snippet = Snippet(
            title: I18n.localized("keydrop_default_title", language: appState.language),
            content: I18n.localized("keydrop_default_content", language: appState.language),
            category: trimmed
        )
        store.add(snippet: snippet)
        browse.selectedCategory = trimmed
        newCategoryNameInput = ""
        // 占位条目只有默认文案，用户多半想立刻改写它，直接推进到编辑页省一次点击
        onOpenEntry(snippet.id)
    }

    private func countForCategory(_ category: String) -> Int {
        if category == KeyDropConstants.categoryAll {
            return store.snippets.count
        }
        return store.snippets.filter { $0.category == category }.count
    }

    private func iconName(for category: String) -> String {
        switch category {
        case KeyDropConstants.categoryAll: return "square.grid.2x2.fill"
        case KeyDropConstants.categoryUncategorized: return "tray.fill"
        default: return "folder.fill"
        }
    }

    private func displayName(for category: String) -> String {
        if category == KeyDropConstants.categoryAll {
            return I18n.localized("keydrop_category_all", language: appState.language)
        } else if category == KeyDropConstants.categoryUncategorized {
            return I18n.localized("keydrop_uncategorized", language: appState.language)
        }
        return category
    }
}
