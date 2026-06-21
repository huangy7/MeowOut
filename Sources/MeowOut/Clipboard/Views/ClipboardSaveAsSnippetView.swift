import SwiftUI

public struct ClipboardSaveAsSnippetView: View {
    private let item: ClipboardItem
    @ObservedObject private var snippetStore: SnippetStore
    @State private var title: String
    @State private var category: String
    @State private var didSave = false

    public init(item: ClipboardItem) {
        self.init(item: item, snippetStore: .shared)
    }

    public init(
        item: ClipboardItem,
        snippetStore: SnippetStore
    ) {
        self.item = item
        self.snippetStore = snippetStore
        _title = State(initialValue: item.title)
        _category = State(initialValue: KeyDropConstants.categoryUncategorized)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)

            TextField("Category", text: $category)
                .textFieldStyle(.roundedBorder)

            Text(previewText ?? "This clipboard item has no text preview.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Spacer()
                Button(didSave ? "Saved" : "Save Snippet") {
                    saveSnippet()
                }
                .disabled(didSave || previewText == nil || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(14)
        .frame(width: 320)
    }

    private var previewText: String? {
        guard item.primaryKind == .text || item.primaryKind == .richText else {
            return nil
        }

        return item.contents
            .lazy
            .compactMap(\.previewText)
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }

    private func saveSnippet() {
        guard !didSave else {
            return
        }

        guard let previewText else {
            return
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            return
        }

        let trimmedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        snippetStore.add(
            snippet: Snippet(
                title: trimmedTitle,
                content: previewText,
                category: trimmedCategory.isEmpty ? KeyDropConstants.categoryUncategorized : trimmedCategory
            )
        )
        didSave = true
    }
}
