// Sources/MeowOut/KeyDrop/Models/KeyDropBrowseState.swift
import Foundation
import Observation
import SwiftUI

/// 常用语工作台的浏览与选中状态：当前分类、搜索词与右侧正在编辑的词条 ID。
/// 由设置窗口持有，切去其他设置页签再切回时，用户的筛选与选中位置不丢失。
@Observable
final class KeyDropBrowseState {
    var selectedCategory: String = KeyDropConstants.categoryAll
    var searchText: String = ""
    var selectedSnippetID: UUID? = nil

    func filteredSnippets(from snippets: [Snippet]) -> [Snippet] {
        let categoryFiltered = selectedCategory == KeyDropConstants.categoryAll
            ? snippets
            : snippets.filter { $0.category == selectedCategory }

        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return categoryFiltered
        }

        return categoryFiltered.filter {
            $0.title.localizedCaseInsensitiveContains(trimmedQuery) ||
            $0.content.localizedCaseInsensitiveContains(trimmedQuery)
        }
    }

    static func reconciledSelection(currentID: UUID?, in filtered: [Snippet]) -> UUID? {
        if let currentID, filtered.contains(where: { $0.id == currentID }) {
            return currentID
        }
        return filtered.first?.id
    }

    static func selectionAfterDeleting(id: UUID, in filtered: [Snippet]) -> UUID? {
        guard let index = filtered.firstIndex(where: { $0.id == id }) else {
            return reconciledSelection(currentID: nil, in: filtered)
        }
        var remaining = filtered
        remaining.remove(at: index)
        guard !remaining.isEmpty else { return nil }
        let nextIndex = min(index, remaining.count - 1)
        return remaining[nextIndex].id
    }

    static func movedSelection(currentID: UUID?, delta: Int, in filtered: [Snippet]) -> UUID? {
        guard !filtered.isEmpty else { return nil }
        guard let currentID, let index = filtered.firstIndex(where: { $0.id == currentID }) else {
            return delta < 0 ? filtered.last?.id : filtered.first?.id
        }
        let targetIndex = min(max(0, index + delta), filtered.count - 1)
        return filtered[targetIndex].id
    }
}

/// 新建常用语草稿模型：仅在用户点击保存时才生成 Snippet 落库，避免取消残留脏数据。
struct SnippetDraft: Equatable {
    static let maxAutoTitleLength = 24

    var sessionID: UUID = UUID()
    var title: String = ""
    var content: String = ""
    var category: String = KeyDropConstants.categoryUncategorized

    init(
        sessionID: UUID = UUID(),
        title: String = "",
        content: String = "",
        category: String = KeyDropConstants.categoryUncategorized
    ) {
        self.sessionID = sessionID
        self.title = title
        self.content = content
        self.category = category
    }

    var hasUnsavedInput: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canSave: Bool {
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var resolvedTitle: String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty {
            return trimmedTitle
        }
        let firstNonEmptyLine = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? ""
        return String(firstNonEmptyLine.prefix(Self.maxAutoTitleLength))
    }

    var resolvedCategory: String {
        let trimmed = category.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != KeyDropConstants.categoryAll else {
            return KeyDropConstants.categoryUncategorized
        }
        return trimmed
    }

    func makeSnippet() -> Snippet {
        Snippet(
            title: resolvedTitle,
            content: content,
            category: resolvedCategory
        )
    }
}

/// 词条内容统计：实时向编辑器顶部反馈行数与字符数。
struct SnippetContentMetrics: Equatable {
    let lineCount: Int
    let characterCount: Int

    static func measure(_ content: String) -> SnippetContentMetrics {
        guard !content.isEmpty else {
            return SnippetContentMetrics(lineCount: 0, characterCount: 0)
        }
        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n").count
        return SnippetContentMetrics(lineCount: lines, characterCount: content.count)
    }
}

/// 分类柔和色标与图标映射：按名称稳定哈希映射到柔和 macOS 语义色，跨启动保持一致。
enum SnippetCategoryStyle {
    private static let palette: [Color] = [
        .blue,
        .green,
        .purple,
        .orange,
        .teal,
        .pink
    ]

    static func paletteIndex(for category: String) -> Int? {
        let trimmed = category.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed != KeyDropConstants.categoryAll,
              trimmed != KeyDropConstants.categoryUncategorized else {
            return nil
        }
        var hash: UInt64 = 5381
        for byte in trimmed.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        return Int(hash % UInt64(palette.count))
    }

    static func tint(for category: String) -> Color? {
        guard let index = paletteIndex(for: category) else { return nil }
        return palette[index]
    }

    static func iconName(for category: String) -> String {
        switch category {
        case KeyDropConstants.categoryAll:
            return "square.grid.2x2"
        case KeyDropConstants.categoryUncategorized, "":
            return "tray"
        default:
            return "folder"
        }
    }
}

