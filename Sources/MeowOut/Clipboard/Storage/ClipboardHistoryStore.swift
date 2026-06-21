import Combine
import Foundation
import os

@MainActor
public final class ClipboardHistoryStore: ObservableObject {
    public static let shared = ClipboardHistoryStore()
    private static let logger = Logger(subsystem: "MeowOut", category: "ClipboardHistoryStore")

    @Published public private(set) var items: [ClipboardItem] = []

    private let storageURL: URL
    private let assetStore: ClipboardAssetStore
    private let settings: ClipboardHistorySettings
    private let fileManager: FileManager

    public convenience init() {
        let applicationSupportDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        let storageURL = applicationSupportDirectory
            .appendingPathComponent("MeowOut", isDirectory: true)
            .appendingPathComponent("clipboard-history.json", isDirectory: false)

        self.init(
            storageURL: storageURL,
            assetStore: .applicationSupportStore,
            settings: .shared
        )
    }

    public init(
        storageURL: URL,
        assetStore: ClipboardAssetStore,
        settings: ClipboardHistorySettings
    ) {
        self.storageURL = storageURL
        self.assetStore = assetStore
        self.settings = settings
        fileManager = .default

        load()
    }

    public func load() {
        guard fileManager.fileExists(atPath: storageURL.path) else {
            items = []
            return
        }

        do {
            let data = try Data(contentsOf: storageURL)
            items = try JSONDecoder().decode([ClipboardItem].self, from: data)
            let removedDuplicateItems = mergeDuplicateItemsWithoutSaving()
            sortItems()
            let removedItems = enforceLimitWithoutSaving()
            let allRemovedItems = removedDuplicateItems + removedItems
            if !allRemovedItems.isEmpty {
                deleteAssets(for: allRemovedItems)
                save()
            }
        } catch {
            backupCorruptStorage()
            items = []
        }
    }

    public func add(_ item: ClipboardItem) {
        var itemToStore = item
        let now = Date()
        itemToStore.lastCopiedAt = now

        items.append(itemToStore)

        let removedDuplicateItems = mergeDuplicateItemsWithoutSaving()
        sortItems()
        let removedItems = enforceLimitWithoutSaving()
        deleteAssets(for: removedDuplicateItems + removedItems)
        save()
    }

    private func mergedItem(
        newItem: ClipboardItem,
        existingItem: ClipboardItem,
        copyCountIncrement: Int,
        lastCopiedAt: Date
    ) -> ClipboardItem {
        var merged = newItem.supersedes(existingItem) ? newItem : existingItem
        merged.lastCopiedAt = lastCopiedAt
        merged.id = existingItem.id
        merged.createdAt = existingItem.createdAt
        merged.copyCount = existingItem.copyCount + copyCountIncrement
        merged.isPinned = existingItem.isPinned || newItem.isPinned

        if !existingItem.title.isEmpty {
            merged.title = existingItem.title
        }

        if existingItem.sourceBundleIdentifier != nil
            || existingItem.sourceApplicationName != nil
            || existingItem.sourceApplicationIconFileName != nil {
            merged.sourceBundleIdentifier = existingItem.sourceBundleIdentifier
            merged.sourceApplicationName = existingItem.sourceApplicationName
            merged.sourceApplicationIconFileName = existingItem.sourceApplicationIconFileName
        }

        return merged
    }

    private func mergeDuplicateItemsWithoutSaving() -> [ClipboardItem] {
        guard items.count > 1 else {
            return []
        }

        var mergedItems: [ClipboardItem] = []
        var removedItems: [ClipboardItem] = []

        for item in items {
            if let existingIndex = mergedItems.firstIndex(where: { existingItem in
                item.supersedes(existingItem)
                    || existingItem.supersedes(item)
                    || existingItem.hasSameEffectiveContents(as: item)
            }) {
                let existingItem = mergedItems[existingIndex]
                let latestCopiedAt = max(existingItem.lastCopiedAt, item.lastCopiedAt)
                mergedItems[existingIndex] = mergedItem(
                    newItem: item,
                    existingItem: existingItem,
                    copyCountIncrement: max(item.copyCount, 1),
                    lastCopiedAt: latestCopiedAt
                )
                removedItems.append(existingItem)
                removedItems.append(item)
            } else {
                mergedItems.append(item)
            }
        }

        items = mergedItems
        return removedItems
    }

    public func togglePinned(_ itemID: UUID) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else {
            return
        }

        items[index].isPinned.toggle()
        sortItems()
        save()
    }

    public func delete(_ itemID: UUID) {
        let removedItems = removeItems { $0.id == itemID }
        deleteAssets(for: removedItems)
        save()
    }

    public func clearUnpinned() {
        let removedItems = removeItems { !$0.isPinned }
        deleteAssets(for: removedItems)
        save()
    }

    public func clearAll() {
        let removedItems = items
        items = []
        deleteAssets(for: removedItems)
        save()
    }

    public func search(_ query: String) -> [ClipboardItem] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return items
        }

        return items.filter { item in
            contains(trimmedQuery, in: item.title)
                || contains(trimmedQuery, in: item.primaryPreview)
                || contains(trimmedQuery, in: item.sourceBundleIdentifier)
                || contains(trimmedQuery, in: item.sourceApplicationName)
        }
    }

    public func save() {
        do {
            try fileManager.createDirectory(
                at: storageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(items)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            Self.logger.error("Failed to save clipboard history at \(self.storageURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            assertionFailure("Failed to save clipboard history: \(error)")
        }
    }

    private func sortItems() {
        items.sort(by: itemSortPrecedes(_:_:))
    }

    private func itemSortPrecedes(_ lhs: ClipboardItem, _ rhs: ClipboardItem) -> Bool {
        if lhs.isPinned != rhs.isPinned {
            return lhs.isPinned && !rhs.isPinned
        }

        switch settings.sortMode {
        case .lastCopiedAt:
            if lhs.lastCopiedAt != rhs.lastCopiedAt {
                return lhs.lastCopiedAt > rhs.lastCopiedAt
            }
        case .createdAt:
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt > rhs.createdAt
            }
        case .copyCount:
            if lhs.copyCount != rhs.copyCount {
                return lhs.copyCount > rhs.copyCount
            }
        }

        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt > rhs.createdAt
        }

        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func enforceLimitWithoutSaving() -> [ClipboardItem] {
        let unpinnedItems = items.filter { !$0.isPinned }
        let excessCount = unpinnedItems.count - settings.historyLimit
        guard excessCount > 0 else {
            return []
        }

        let removedIDs = Set(
            unpinnedItems
                .sorted {
                    if $0.lastCopiedAt != $1.lastCopiedAt {
                        return $0.lastCopiedAt < $1.lastCopiedAt
                    }

                    return $0.createdAt < $1.createdAt
                }
                .prefix(excessCount)
                .map(\.id)
        )

        return removeItems { removedIDs.contains($0.id) }
    }

    private func removeItems(where shouldRemove: (ClipboardItem) -> Bool) -> [ClipboardItem] {
        let removedItems = items.filter(shouldRemove)
        guard !removedItems.isEmpty else {
            return []
        }

        items.removeAll(where: shouldRemove)
        return removedItems
    }

    private func deleteAssets(for removedItems: [ClipboardItem]) {
        guard !removedItems.isEmpty else {
            return
        }

        let remainingAssetFileNames = assetFileNames(in: items)
        let removedAssetFileNames = assetFileNames(in: removedItems)
            .subtracting(remainingAssetFileNames)

        for fileName in removedAssetFileNames {
            try? assetStore.delete(fileName: fileName)
        }
    }

    private func assetFileNames(in items: [ClipboardItem]) -> Set<String> {
        Set(items.flatMap { item in
            var fileNames = item.contents.compactMap { content in
                if case let .asset(fileName) = content.storage {
                    return fileName
                }

                return nil
            }

            if let sourceApplicationIconFileName = item.sourceApplicationIconFileName {
                fileNames.append(sourceApplicationIconFileName)
            }

            return fileNames
        })
    }

    private func contains(_ query: String, in value: String?) -> Bool {
        guard let value else {
            return false
        }

        return value.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    private func backupCorruptStorage() {
        let directory = storageURL.deletingLastPathComponent()
        let baseName = storageURL.deletingPathExtension().lastPathComponent
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backupURL = directory.appendingPathComponent("\(baseName)-corrupt-\(timestamp)-\(UUID().uuidString).json")

        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try fileManager.copyItem(at: storageURL, to: backupURL)
            try fileManager.removeItem(at: storageURL)
        } catch {
            Self.logger.error("Failed to back up corrupt clipboard history at \(self.storageURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
