import SwiftUI

struct SnippetEditorView: View {
    @ObservedObject var store = SnippetStore.shared
    @Bindable var state: AppState
    
    @State private var editingSnippetId: UUID? = nil
    @State private var editTitle: String = ""
    @State private var editContent: String = ""
    @State private var editCategory: String = ""
    @State private var isNewCategory: Bool = false
    @State private var newCategoryName: String = ""
    
    @State private var collapsedCategories: Set<String> = []
    @State private var showingAddCategoryAlert = false
    @State private var newCategoryNameInput = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text(I18n.localized("settings_subtab_snippets", language: state.language))
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                HStack(spacing: 8) {
                    Button(action: { showingAddCategoryAlert = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: "folder.badge.plus")
                            Text(I18n.localized("keydrop_add_category_btn", language: state.language))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    Button(action: addSnippet) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                            Text(I18n.localized("keydrop_add_btn", language: state.language))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            
            // List of snippets grouped by category
            ScrollView(showsIndicators: false) {
                let grouped = Dictionary(grouping: store.snippets, by: { $0.category })
                let sortedCategories = grouped.keys.sorted { a, b in
                    if a == KeyDropConstants.categoryUncategorized { return false }
                    if b == KeyDropConstants.categoryUncategorized { return true }
                    return a < b
                }
                
                VStack(spacing: 10) {
                    ForEach(sortedCategories, id: \.self) { category in
                        let snippets = grouped[category] ?? []
                        VStack(alignment: .leading, spacing: 6) {
                            Button(action: {
                                withAnimation {
                                    if collapsedCategories.contains(category) {
                                        collapsedCategories.remove(category)
                                    } else {
                                        collapsedCategories.insert(category)
                                    }
                                }
                            }) {
                                HStack {
                                    Image(systemName: collapsedCategories.contains(category) ? "chevron.right" : "chevron.down")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.secondary)
                                    Text(category)
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Text("\(snippets.count)")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.primary.opacity(0.06))
                                        .cornerRadius(6)
                                }
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            
                            if !collapsedCategories.contains(category) {
                                VStack(spacing: 8) {
                                    ForEach(snippets) { snippet in
                                        if editingSnippetId == snippet.id {
                                            VStack(alignment: .leading, spacing: 8) {
                                                HStack(spacing: 8) {
                                                    TextField(I18n.localized("keydrop_title_placeholder", language: state.language), text: $editTitle)
                                                        .textFieldStyle(.roundedBorder)
                                                        .font(.system(size: 12))
                                                    Spacer()
                                                    Button(I18n.localized("keydrop_save_btn", language: state.language)) {
                                                        saveSnippet(snippet)
                                                    }
                                                    .buttonStyle(.borderedProminent)
                                                    .controlSize(.small)
                                                    
                                                    Button(I18n.localized("keydrop_cancel_btn", language: state.language)) {
                                                        editingSnippetId = nil
                                                    }
                                                    .buttonStyle(.bordered)
                                                    .controlSize(.small)
                                                }
                                                
                                                HStack(spacing: 8) {
                                                    Text(I18n.localized("keydrop_category_label", language: state.language))
                                                        .font(.system(size: 11))
                                                        .foregroundColor(.secondary)
                                                    let existingCategories = Array(Set(store.snippets.map { $0.category } + [KeyDropConstants.categoryUncategorized])).filter { !$0.isEmpty }.sorted()
                                                    
                                                    Picker("", selection: Binding(
                                                        get: { isNewCategory ? "NEW_CATEGORY" : editCategory },
                                                        set: { val in
                                                            if val == "NEW_CATEGORY" {
                                                                isNewCategory = true
                                                            } else {
                                                                isNewCategory = false
                                                                editCategory = val
                                                            }
                                                        }
                                                    )) {
                                                        ForEach(existingCategories, id: \.self) { cat in
                                                            Text(cat).tag(cat)
                                                        }
                                                        Text(I18n.localized("keydrop_category_new_option", language: state.language)).tag("NEW_CATEGORY")
                                                    }
                                                    .pickerStyle(.menu)
                                                    .labelsHidden()
                                                    .controlSize(.small)
                                                    
                                                    if isNewCategory {
                                                        TextField(I18n.localized("keydrop_category_placeholder", language: state.language), text: $newCategoryName)
                                                            .textFieldStyle(.roundedBorder)
                                                            .font(.system(size: 11))
                                                            .frame(width: 120)
                                                    }
                                                    Spacer()
                                                }
                                                
                                                TextEditor(text: $editContent)
                                                    .frame(height: 50)
                                                    .font(.system(size: 11))
                                                    .padding(4)
                                                    .background(Color(nsColor: .textBackgroundColor).opacity(0.8))
                                                    .cornerRadius(6)
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 6)
                                                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                                                    )
                                            }
                                            .padding(10)
                                            .background(Color.primary.opacity(0.04))
                                            .cornerRadius(10)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 10)
                                                    .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
                                            )
                                        } else {
                                            HStack {
                                                VStack(alignment: .leading, spacing: 3) {
                                                    Text(snippet.title)
                                                        .font(.system(size: 13, weight: .semibold))
                                                    Text(snippet.content)
                                                        .font(.system(size: 11))
                                                        .foregroundColor(.secondary)
                                                        .lineLimit(1)
                                                }
                                                Spacer()
                                                HStack(spacing: 12) {
                                                    Button(action: {
                                                        startEditing(snippet)
                                                    }) {
                                                        Image(systemName: "pencil")
                                                            .font(.system(size: 12))
                                                            .foregroundColor(.secondary)
                                                    }
                                                    .buttonStyle(.plain)
                                                    .help(I18n.localized("keydrop_save_btn", language: state.language))
                                                    
                                                    Button(action: {
                                                        store.delete(snippet: snippet)
                                                    }) {
                                                        Image(systemName: "trash")
                                                            .font(.system(size: 12))
                                                            .foregroundColor(.red.opacity(0.7))
                                                    }
                                                    .buttonStyle(.plain)
                                                }
                                            }
                                            .padding(.vertical, 8)
                                            .padding(.horizontal, 12)
                                            .background(Color(nsColor: .windowBackgroundColor).opacity(0.4))
                                            .cornerRadius(10)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 10)
                                                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                                            )
                                        }
                                    }
                                }
                                .padding(.leading, 12)
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: 280)
        }
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.3))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
        .alert(I18n.localized("keydrop_add_category_title", language: state.language), isPresented: $showingAddCategoryAlert) {
            TextField(I18n.localized("keydrop_add_category_placeholder", language: state.language), text: $newCategoryNameInput)
            Button(I18n.localized("keydrop_save_btn", language: state.language)) {
                addNewCategory()
            }
            Button(I18n.localized("keydrop_cancel_btn", language: state.language), role: .cancel) {
                newCategoryNameInput = ""
            }
        } message: {
            Text(I18n.localized("keydrop_add_category_prompt", language: state.language))
        }
    }
    
    private func startEditing(_ snippet: Snippet) {
        editingSnippetId = snippet.id
        editTitle = snippet.title
        editContent = snippet.content
        editCategory = snippet.category
        isNewCategory = false
        newCategoryName = ""
    }
    
    private func saveSnippet(_ snippet: Snippet) {
        guard !editTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        var updated = snippet
        updated.title = editTitle
        updated.content = editContent
        if isNewCategory {
            let trimmed = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
            updated.category = trimmed.isEmpty ? KeyDropConstants.categoryUncategorized : trimmed
        } else {
            updated.category = editCategory.isEmpty ? KeyDropConstants.categoryUncategorized : editCategory
        }
        store.update(snippet: updated)
        editingSnippetId = nil
    }
    
    private func addSnippet() {
        let newSnippet = Snippet(
            title: I18n.localized("keydrop_default_title", language: state.language),
            content: I18n.localized("keydrop_default_content", language: state.language),
            category: KeyDropConstants.categoryUncategorized
        )
        store.add(snippet: newSnippet)
        startEditing(newSnippet)
    }
    
    private func addNewCategory() {
        let trimmed = newCategoryNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let newSnippet = Snippet(
            title: I18n.localized("keydrop_default_title", language: state.language),
            content: I18n.localized("keydrop_default_content", language: state.language),
            category: trimmed
        )
        store.add(snippet: newSnippet)
        startEditing(newSnippet)
        newCategoryNameInput = ""
    }
}

