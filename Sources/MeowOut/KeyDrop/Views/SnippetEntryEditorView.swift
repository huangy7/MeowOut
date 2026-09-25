// Sources/MeowOut/KeyDrop/Views/SnippetEntryEditorView.swift
import SwiftUI
import AppKit

/// 单条常用语的编辑页。占满设置详情面板宽度，由列表页推进而来。
/// 名称是内容的第一行，不在工具栏重复；值是一条随内容增长的有边框行，不是全高编辑框。
struct SnippetEntryEditorView: View {
    @Environment(AppState.self) private var appState
    @ObservedObject var store = SnippetStore.shared

    let entryID: UUID

    @State private var title = ""
    @State private var content = ""
    @State private var category = KeyDropConstants.categoryUncategorized
    @State private var isLoaded = false
    @State private var didCopy = false

    private var selectableCategories: [String] {
        let list = store.snippets.map { $0.category }
        var unique = Array(Set(list)).filter { !$0.isEmpty && $0 != KeyDropConstants.categoryUncategorized }.sorted()
        if list.contains(KeyDropConstants.categoryUncategorized) {
            unique.append(KeyDropConstants.categoryUncategorized)
        }
        return unique
    }

    var body: some View {
        if store.snippets.contains(where: { $0.id == entryID }) {
            VStack(alignment: .leading, spacing: 20) {
                titleField
                valueSection
                categoryRow
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onAppear(perform: load)
            .onChange(of: title) { _, _ in save() }
            .onChange(of: content) { _, _ in save() }
            .onChange(of: category) { _, _ in save() }
        } else {
            // 条目已不存在（例如在别处被删除）：不崩溃、不停留在空页面。
            // 文案只说这一条没了，不能说成"一条常用语都没有"。
            ContentUnavailableView(
                I18n.localized("keydrop_entry_missing", language: appState.language),
                systemImage: "keyboard"
            )
        }
    }

    // MARK: - 名称

    private var titleField: some View {
        TextField(I18n.localized("keydrop_title_placeholder", language: appState.language), text: $title)
            .textFieldStyle(.plain)
            .font(.title3.weight(.semibold))
    }

    // MARK: - 值

    private var valueSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(I18n.localized("keydrop_value_label", language: appState.language))
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 8) {
                TextField("", text: $content, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .lineLimit(1...)

                Button(action: copyValue) {
                    Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(I18n.localized(didCopy ? "keydrop_copied" : "keydrop_copy_value", language: appState.language))
                .accessibilityLabel(I18n.localized("keydrop_copy_value", language: appState.language))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.primary.opacity(0.15), lineWidth: 1)
            )
        }
    }

    // MARK: - 分类

    private var categoryRow: some View {
        HStack(spacing: 12) {
            Picker("", selection: $category) {
                ForEach(selectableCategories, id: \.self) { cat in
                    Text(displayName(for: cat)).tag(cat)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            // 设计上不放可见的「分类」标签，但弹出按钮不能因此没有名字，
            // 否则 VoiceOver 只会念出一个孤零零的当前值。
            .accessibilityLabel(I18n.localized("keydrop_category_label", language: appState.language))
            .fixedSize()

            Spacer(minLength: 0)
        }
    }

    // MARK: - 动作

    private func load() {
        guard let snippet = store.snippets.first(where: { $0.id == entryID }) else { return }
        title = snippet.title
        content = snippet.content
        category = snippet.category
        isLoaded = true
    }

    private func save() {
        guard isLoaded,
              let original = store.snippets.first(where: { $0.id == entryID }) else { return }
        guard original.title != title || original.content != content || original.category != category else { return }

        var updated = original
        updated.title = title
        updated.content = content
        updated.category = category.isEmpty ? KeyDropConstants.categoryUncategorized : category
        store.update(snippet: updated)
    }

    private func copyValue() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
        didCopy = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            didCopy = false
        }
    }

    private func displayName(for category: String) -> String {
        if category == KeyDropConstants.categoryUncategorized {
            return I18n.localized("keydrop_uncategorized", language: appState.language)
        }
        return category
    }
}
