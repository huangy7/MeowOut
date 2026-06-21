import Combine
import Foundation

public struct ClipboardPreviewMetadata: Equatable, Sendable {
    public let sourceName: String?
    public let firstCopiedAt: Date
    public let lastCopiedAt: Date
    public let copyCount: Int

    public init(
        sourceName: String?,
        firstCopiedAt: Date,
        lastCopiedAt: Date,
        copyCount: Int
    ) {
        self.sourceName = sourceName
        self.firstCopiedAt = firstCopiedAt
        self.lastCopiedAt = lastCopiedAt
        self.copyCount = copyCount
    }
}

public struct ClipboardPanelRowModel: Identifiable, Equatable, Sendable {
    public let filteredIndex: Int
    public let item: ClipboardItem

    public var id: String {
        "\(filteredIndex)-\(item.id.uuidString)"
    }

    public init(filteredIndex: Int, item: ClipboardItem) {
        self.filteredIndex = filteredIndex
        self.item = item
    }
}

@MainActor
public final class ClipboardPanelViewModel: ObservableObject {
    @Published public var searchText: String = "" {
        didSet {
            guard searchText != oldValue else { return }
            selectIndex(0, scroll: true)
        }
    }

    @Published public var selectedIndex: Int = 0
    @Published public var shouldScroll: Bool = false

    private let store: ClipboardHistoryStore
    private let settings: ClipboardHistorySettings
    private let pasteService: ClipboardPasteService
    private var cancellables = Set<AnyCancellable>()

    public convenience init() {
        self.init(
            store: .shared,
            settings: .shared,
            pasteService: .shared
        )
    }

    public init(
        store: ClipboardHistoryStore,
        settings: ClipboardHistorySettings,
        pasteService: ClipboardPasteService = .shared
    ) {
        self.store = store
        self.settings = settings
        self.pasteService = pasteService

        store.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    public var filteredItems: [ClipboardItem] {
        store.search(searchText)
    }

    public var filteredRows: [ClipboardPanelRowModel] {
        filteredItems.enumerated().map { index, item in
            ClipboardPanelRowModel(filteredIndex: index, item: item)
        }
    }

    public var selectedRowID: ClipboardPanelRowModel.ID? {
        filteredRows.first { $0.filteredIndex == selectedIndex }?.id
    }

    public var pinnedItems: [ClipboardItem] {
        filteredItems.filter(\.isPinned)
    }

    public var unpinnedItems: [ClipboardItem] {
        filteredItems.filter { !$0.isPinned }
    }

    public var pinnedRows: [ClipboardPanelRowModel] {
        filteredRows.filter(\.item.isPinned)
    }

    public var unpinnedRows: [ClipboardPanelRowModel] {
        filteredRows.filter { !$0.item.isPinned }
    }

    public var selectedItem: ClipboardItem? {
        item(at: selectedIndex)
    }

    public var selectedPreviewMetadata: ClipboardPreviewMetadata? {
        guard let item = selectedItem else {
            return nil
        }

        return ClipboardPreviewMetadata(
            sourceName: item.sourceApplicationName ?? item.sourceBundleIdentifier,
            firstCopiedAt: item.createdAt,
            lastCopiedAt: item.lastCopiedAt,
            copyCount: item.copyCount
        )
    }

    public func reset() {
        searchText = ""
        selectIndex(0, scroll: true)
    }

    public func moveSelection(up: Bool) {
        let count = filteredItems.count
        guard count > 0 else {
            selectIndex(0, scroll: false)
            return
        }

        let normalizedIndex = min(max(selectedIndex, 0), count - 1)
        let nextIndex = up
            ? (normalizedIndex - 1 + count) % count
            : (normalizedIndex + 1) % count
        selectIndex(nextIndex, scroll: true)
    }

    public func selectIndex(_ index: Int, scroll: Bool) {
        selectedIndex = clampedIndex(index)
        shouldScroll = scroll
    }

    public func item(at index: Int) -> ClipboardItem? {
        let items = filteredItems
        guard index >= 0, index < items.count else {
            return nil
        }

        return items[index]
    }

    public func appendSearch(_ characters: String) {
        searchText.append(characters)
    }

    @discardableResult
    public func removeLastSearchCharacter() -> Bool {
        guard !searchText.isEmpty else {
            return false
        }

        searchText.removeLast()
        return true
    }

    public func chooseSelected(
        removeFormatting: Bool = false,
        pasteAutomaticallyOverride: Bool? = nil
    ) {
        guard let item = selectedItem else {
            return
        }

        choose(
            item,
            removeFormatting: removeFormatting,
            pasteAutomaticallyOverride: pasteAutomaticallyOverride
        )
    }

    @discardableResult
    public func chooseItem(
        at index: Int,
        removeFormatting: Bool = false,
        pasteAutomaticallyOverride: Bool? = nil
    ) -> Bool {
        guard let item = item(at: index) else {
            return false
        }

        selectIndex(index, scroll: false)
        choose(
            item,
            removeFormatting: removeFormatting,
            pasteAutomaticallyOverride: pasteAutomaticallyOverride
        )
        return true
    }

    public func togglePinnedSelected() {
        guard let item = selectedItem else {
            return
        }

        store.togglePinned(item.id)
        keepSelectionValid()
    }

    public func deleteSelected() {
        guard let item = selectedItem else {
            return
        }

        store.delete(item.id)
        keepSelectionValid()
    }

    public func clearUnpinned() {
        store.clearUnpinned()
        keepSelectionValid()
    }

    private func choose(
        _ item: ClipboardItem,
        removeFormatting: Bool,
        pasteAutomaticallyOverride: Bool?
    ) {
        pasteService.copy(
            item,
            removeFormatting: removeFormatting || settings.removeFormattingByDefault,
            pasteAutomatically: pasteAutomaticallyOverride ?? settings.pasteAutomatically
        )
    }

    private func keepSelectionValid() {
        selectedIndex = clampedIndex(selectedIndex)
        shouldScroll = true
    }

    private func clampedIndex(_ index: Int) -> Int {
        let count = filteredItems.count
        guard count > 0 else {
            return 0
        }

        return min(max(index, 0), count - 1)
    }
}
