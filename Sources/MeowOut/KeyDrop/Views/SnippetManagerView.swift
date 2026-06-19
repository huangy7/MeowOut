import SwiftUI
import UniformTypeIdentifiers

struct SnippetManagerView: View {
    @Environment(AppState.self) private var appState
    @ObservedObject var store = SnippetStore.shared
    
    @State private var selectedCategory: String = KeyDropConstants.categoryAll
    @State private var selectedSnippetId: UUID? = nil
    @State private var searchText: String = ""
    @State private var draggedSnippet: Snippet? = nil
    @State private var targetedCategory: String? = nil
    
    // Editor State
    @State private var editTitle: String = ""
    @State private var editContent: String = ""
    @State private var editCategory: String = KeyDropConstants.categoryUncategorized
    
    // Category Alert State
    @State private var showingAddCategoryAlert = false
    @State private var newCategoryNameInput = ""
    @State private var showingRenameCategoryAlert = false
    @State private var showingMergeWarningAlert = false
    @State private var categoryToRename: String = ""
    @State private var newCategoryNameForRename: String = ""
    

    
    // Collapsible Columns State
    @State private var isSidebarVisible = true
    @State private var isListVisible = true
    
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
        let categoryFiltered = selectedCategory == KeyDropConstants.categoryAll ? all : all.filter { $0.category == selectedCategory }
        if searchText.isEmpty {
            return categoryFiltered
        }
        return categoryFiltered.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.content.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Left Sidebar: Categories
            if isSidebarVisible {
                sidebarView
                    .frame(width: 200)
                    .background(CustomVisualEffectView(material: .sidebar))
                    .transition(.move(edge: .leading))
                
                Divider()
            }
            
            // Middle List: Snippets
            if isListVisible {
                listView
                    .frame(width: 240)
                    .background(CustomVisualEffectView(material: .titlebar))
                    .transition(.move(edge: .leading))
                
                Divider()
            }
            
            // Right Detail: Editor
            editorView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(CustomVisualEffectView(material: .windowBackground))
        }
        .frame(minWidth: 800, minHeight: 600)
        .onAppear {
            if let first = filteredSnippets.first {
                selectSnippet(first)
            }
        }
        .onChange(of: selectedCategory) { _, _ in
            let list = filteredSnippets
            if let first = list.first {
                selectSnippet(first)
            } else {
                selectSnippet(nil)
            }
        }
        .onChange(of: searchText) { _, _ in
            let list = filteredSnippets
            if let selectedId = selectedSnippetId {
                if !list.contains(where: { $0.id == selectedId }) {
                    selectSnippet(list.first)
                }
            } else {
                selectSnippet(list.first)
            }
        }
        // Auto-save triggers
        .onChange(of: editTitle) { _, _ in saveCurrentChanges() }
        .onChange(of: editContent) { _, _ in saveCurrentChanges() }
        .onChange(of: editCategory) { _, _ in saveCurrentChanges() }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isSidebarVisible.toggle()
                    }
                }) {
                    Image(systemName: "sidebar.left")
                }
                .keyboardShortcut("b", modifiers: .command)
                .help("\(I18n.localized("keydrop_category_label", language: appState.language)) (⌘B)")
                
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isListVisible.toggle()
                    }
                }) {
                    Image(systemName: "list.bullet")
                }
                .keyboardShortcut("l", modifiers: .command)
                .help("\(I18n.localized("settings_tab_keydrop", language: appState.language)) (⌘L)")
            }
        }
    }
    
    // MARK: - Left Sidebar
    private var sidebarView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(I18n.localized("keydrop_category_label", language: appState.language))
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)
            
            categoriesListView
            
            Spacer()
            
            Divider()
            
            // Add Category Button
            HStack {
                Button(action: {
                    showingAddCategoryAlert = true
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(I18n.localized("keydrop_add_category_btn", language: appState.language))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
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
    }
    
    private var categoriesListView: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(categories, id: \.self) { category in
                    categoryButton(for: category)
                }
            }
            .padding(.horizontal, 8)
        }
        .alert(I18n.localized("keydrop_rename_category", language: appState.language), isPresented: $showingRenameCategoryAlert) {
            TextField("", text: $newCategoryNameForRename)
            Button(I18n.localized("keydrop_save_btn", language: appState.language)) {
                let trimmed = newCategoryNameForRename.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, trimmed != categoryToRename, trimmed != KeyDropConstants.categoryAll else { return }
                
                let allCategories = store.snippets.map { $0.category }
                if allCategories.contains(trimmed) {
                    // Category already exists, show merge warning
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        showingMergeWarningAlert = true
                    }
                } else {
                    store.renameCategory(oldName: categoryToRename, newName: trimmed)
                    if selectedCategory == categoryToRename {
                        selectedCategory = trimmed
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
                if selectedCategory == categoryToRename {
                    selectedCategory = trimmed
                }
            }
            Button(I18n.localized("keydrop_cancel_btn", language: appState.language), role: .cancel) {
                newCategoryNameForRename = ""
            }
        } message: {
            Text(I18n.localized("keydrop_merge_warning_message", language: appState.language))
        }
    }

    private func categoryButton(for category: String) -> some View {
        Button(action: {
            selectedCategory = category
        }) {
            HStack {
                Image(systemName: iconName(for: category))
                    .font(.system(size: 12))
                    .frame(width: 16)
                
                Text(displayName(for: category))
                    .font(.system(size: 13, weight: selectedCategory == category ? .semibold : .regular))
                    .lineLimit(1)
                
                Spacer()
                
                Text("\(countForCategory(category))")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(selectedCategory == category ? .white.opacity(0.9) : .secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(selectedCategory == category ? Color.white.opacity(0.2) : Color.primary.opacity(0.06))
                    .cornerRadius(6)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                targetedCategory == category ? Color.accentColor.opacity(0.5) :
                (selectedCategory == category ? Color.accentColor : Color.clear)
            )
            .foregroundColor(selectedCategory == category ? .white : .primary)
            .contentShape(Rectangle())
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if category != KeyDropConstants.categoryAll {
                Button(I18n.localized("keydrop_rename_category", language: appState.language)) {
                    categoryToRename = category
                    // If the category is the localized "Uncategorized", maybe we can pre-fill it or keep it empty. 
                    // Keeping the actual name is fine.
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
    
    // MARK: - Middle List
    private var listView: some View {
        VStack(spacing: 0) {
            // Search Bar
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                    TextField(I18n.localized("keydrop_search_placeholder", language: appState.language), text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                    
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.06))
                .cornerRadius(8)
            }
            .padding(.horizontal, 12)
            .padding(.top, 16)
            .padding(.bottom, 12)
            

            Divider()
            
            // List of Snippets
            if filteredSnippets.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "keyboard")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text(store.snippets.isEmpty ? "No snippets yet" : "No results")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(filteredSnippets) { snippet in
                            Button(action: {
                                selectSnippet(snippet)
                            }) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(snippet.title.isEmpty ? "Untitled" : snippet.title)
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(selectedSnippetId == snippet.id ? .white : .primary)
                                        .lineLimit(1)
                                    
                                    Text(snippet.content.isEmpty ? "No content" : snippet.content)
                                        .font(.system(size: 11))
                                        .foregroundColor(selectedSnippetId == snippet.id ? .white.opacity(0.85) : .secondary)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(selectedSnippetId == snippet.id ? Color.accentColor : Color.clear)
                                .contentShape(Rectangle())
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                            .onDrag {
                                self.draggedSnippet = snippet
                                return NSItemProvider(object: snippet.id.uuidString as NSString)
                            }
                            .onDrop(of: [UTType.text], delegate: SnippetDropDelegate(
                                item: snippet,
                                items: filteredSnippets,
                                draggedItem: $draggedSnippet,
                                searchText: searchText,
                                store: store
                            ))
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                }
            }
            
            Divider()
            
            // Bottom Toolbar for Add/Remove
            HStack(spacing: 16) {
                Button(action: addSnippet) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Add new snippet to current category")
                
                Button(action: deleteSnippet) {
                    Image(systemName: "minus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(selectedSnippetId == nil ? .secondary.opacity(0.3) : .secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(selectedSnippetId == nil)
                .help(I18n.localized("keydrop_delete_snippet", language: appState.language))
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
    }
    
    // MARK: - Right Detail Editor
    @ViewBuilder
    private var editorView: some View {
        if let selectedId = selectedSnippetId,
           let _ = store.snippets.first(where: { $0.id == selectedId }) {
            VStack(alignment: .leading, spacing: 0) {
                // Header Details Form
                VStack(alignment: .leading, spacing: 16) {
                    // Title TextField
                    TextField(I18n.localized("keydrop_title_placeholder", language: appState.language), text: $editTitle)
                        .textFieldStyle(.plain)
                        .font(.system(size: 22, weight: .bold))
                        .padding(.top, 16)
                    
                    Divider()
                    
                    // Category Selection Picker
                    HStack(spacing: 12) {
                        Label {
                            Text(I18n.localized("keydrop_category_label", language: appState.language))
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.secondary)
                        } icon: {
                            Image(systemName: "folder")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        
                        let selectables = categories.filter { $0 != KeyDropConstants.categoryAll }
                        
                        Picker("", selection: $editCategory) {
                            ForEach(selectables, id: \.self) { cat in
                                Text(displayName(for: cat)).tag(cat)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 140)
                        
                        Spacer()
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
                
                Divider()
                
                // Body Content TextEditor
                TextEditor(text: $editContent)
                    .font(.system(size: 14, design: .monospaced))
                    .padding(16)
                    .background(Color.clear)
            }

        } else {
            // Empty State
            VStack(spacing: 16) {
                Image(systemName: "keyboard")
                    .font(.system(size: 48, weight: .thin))
                    .foregroundColor(.secondary.opacity(0.4))
                
                Text(I18n.localized("keydrop_manager_empty_selection", language: appState.language))
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 48)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    // MARK: - Actions & Helpers
    private func selectSnippet(_ snippet: Snippet?) {
        // Save current changes first
        saveCurrentChanges()
        
        if let snippet = snippet {
            selectedSnippetId = snippet.id
            editTitle = snippet.title
            editContent = snippet.content
            editCategory = snippet.category
        } else {
            selectedSnippetId = nil
            editTitle = ""
            editContent = ""
            editCategory = KeyDropConstants.categoryUncategorized
        }
    }
    
    private func saveCurrentChanges() {
        guard let selectedId = selectedSnippetId,
              let original = store.snippets.first(where: { $0.id == selectedId }) else { return }
        
        if original.title != editTitle || original.content != editContent || original.category != editCategory {
            var updated = original
            updated.title = editTitle
            updated.content = editContent
            updated.category = editCategory.isEmpty ? KeyDropConstants.categoryUncategorized : editCategory
            store.update(snippet: updated)
        }
    }
    
    private func addSnippet() {
        let cat = selectedCategory == KeyDropConstants.categoryAll ? KeyDropConstants.categoryUncategorized : selectedCategory
        let newSnippet = Snippet(
            title: I18n.localized("keydrop_default_title", language: appState.language),
            content: I18n.localized("keydrop_default_content", language: appState.language),
            category: cat
        )
        store.add(snippet: newSnippet)
        selectSnippet(newSnippet)
    }
    
    private func deleteSnippet() {
        guard let selectedId = selectedSnippetId,
              let snippet = store.snippets.first(where: { $0.id == selectedId }) else { return }
        
        store.delete(snippet: snippet)
        
        // Find next snippet to select
        let list = filteredSnippets
        selectSnippet(list.first)
    }
    
    private func addNewCategory() {
        let trimmed = newCategoryNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Create a dummy snippet in this category so it shows up in categories list
        let newSnippet = Snippet(
            title: I18n.localized("keydrop_default_title", language: appState.language),
            content: I18n.localized("keydrop_default_content", language: appState.language),
            category: trimmed
        )
        store.add(snippet: newSnippet)
        selectedCategory = trimmed
        selectSnippet(newSnippet)
        newCategoryNameInput = ""
    }
    

    
    private func countForCategory(_ category: String) -> Int {
        if category == KeyDropConstants.categoryAll {
            return store.snippets.count
        } else {
            return store.snippets.filter { $0.category == category }.count
        }
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

// MARK: - Custom Visual Effect View
struct CustomVisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
