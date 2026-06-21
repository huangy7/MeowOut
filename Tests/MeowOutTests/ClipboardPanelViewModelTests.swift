import Foundation
import XCTest
@testable import MeowOut

@MainActor
final class ClipboardPanelViewModelTests: XCTestCase {
    private var root: URL!
    private var historyURL: URL!
    private var assetStore: ClipboardAssetStore!
    private var settings: ClipboardHistorySettings!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardPanelViewModelTests-\(UUID().uuidString)", isDirectory: true)
        historyURL = root.appendingPathComponent("clipboard-history.json")
        assetStore = ClipboardAssetStore(rootDirectory: root.appendingPathComponent("Assets", isDirectory: true))
        suiteName = "ClipboardPanelViewModelTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        settings = ClipboardHistorySettings(defaults: defaults)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
        defaults.removePersistentDomain(forName: suiteName)
        root = nil
        historyURL = nil
        assetStore = nil
        settings = nil
        defaults = nil
        suiteName = nil
    }

    func testSearchFiltersAndSelectionReturnsMatchingItem() {
        let store = makeStoreLoadedWith([
            makeTextItem("alpha", preview: "first"),
            makeTextItem("beta", preview: "needle"),
            makeTextItem("gamma", preview: "third"),
        ])
        let viewModel = ClipboardPanelViewModel(store: store, settings: settings)

        viewModel.searchText = "needle"

        XCTAssertEqual(viewModel.filteredItems.map(\.title), ["beta"])
        XCTAssertEqual(viewModel.selectedItem?.title, "beta")
    }

    func testDeleteSelectedRemovesItem() {
        let store = makeStoreLoadedWith([
            makeTextItem("first"),
            makeTextItem("second"),
        ])
        let viewModel = ClipboardPanelViewModel(store: store, settings: settings)
        viewModel.searchText = "second"

        viewModel.deleteSelected()

        XCTAssertEqual(store.items.map(\.title), ["first"])
        XCTAssertEqual(viewModel.selectedIndex, 0)
    }

    func testMoveSelectionWraps() {
        let store = makeStoreLoadedWith([
            makeTextItem("first"),
            makeTextItem("second"),
            makeTextItem("third"),
        ])
        let viewModel = ClipboardPanelViewModel(store: store, settings: settings)

        viewModel.moveSelection(up: true)
        XCTAssertEqual(viewModel.selectedIndex, 2)

        viewModel.moveSelection(up: false)
        XCTAssertEqual(viewModel.selectedIndex, 0)
    }

    func testChooseSelectedRespectsSettingsAndOverride() {
        settings.removeFormattingByDefault = true
        settings.pasteAutomatically = false
        let writer = FakeClipboardPanelPasteboardWriter()
        let poster = FakeClipboardPanelPasteEventPoster()
        let pasteService = ClipboardPasteService(
            writer: writer,
            eventPoster: poster,
            canPasteAutomatically: { true }
        )
        let store = makeStoreLoadedWith([
            makeRichTextItem("rich", plainText: "plain", richData: Data([1, 2, 3])),
        ])
        let viewModel = ClipboardPanelViewModel(
            store: store,
            settings: settings,
            pasteService: pasteService
        )

        viewModel.chooseSelected(removeFormatting: false, pasteAutomaticallyOverride: true)

        XCTAssertEqual(writer.values["public.utf8-plain-text"], Data("plain".utf8))
        XCTAssertNil(writer.values["public.rtf"])
        XCTAssertEqual(poster.pasteCount, 1)
    }

    func testChooseItemReturnsFalseAndDoesNotPasteForMissingIndex() {
        let writer = FakeClipboardPanelPasteboardWriter()
        let poster = FakeClipboardPanelPasteEventPoster()
        let pasteService = ClipboardPasteService(
            writer: writer,
            eventPoster: poster,
            canPasteAutomatically: { true }
        )
        let store = makeStoreLoadedWith([
            makeTextItem("only"),
        ])
        let viewModel = ClipboardPanelViewModel(
            store: store,
            settings: settings,
            pasteService: pasteService
        )

        let didChoose = viewModel.chooseItem(at: 8)

        XCTAssertFalse(didChoose)
        XCTAssertTrue(writer.values.isEmpty)
        XCTAssertEqual(poster.pasteCount, 0)
        XCTAssertEqual(viewModel.selectedIndex, 0)
    }

    func testTogglePinnedSelectedTogglesStoreState() {
        let item = makeTextItem("pin me")
        let store = makeStoreLoadedWith([item])
        let viewModel = ClipboardPanelViewModel(store: store, settings: settings)

        viewModel.togglePinnedSelected()

        XCTAssertTrue(store.items.first?.isPinned == true)
    }

    func testClearUnpinnedPreservesPinned() {
        var pinned = makeTextItem("pinned")
        pinned.isPinned = true
        let store = makeStoreLoadedWith([
            pinned,
            makeTextItem("temporary"),
        ])
        let viewModel = ClipboardPanelViewModel(store: store, settings: settings)

        viewModel.clearUnpinned()

        XCTAssertEqual(store.items.map(\.title), ["pinned"])
    }

    func testPinnedAndUnpinnedItemsUseFilteredItems() {
        var matchingPinned = makeTextItem("match pinned")
        matchingPinned.isPinned = true
        var unrelatedPinned = makeTextItem("other pinned")
        unrelatedPinned.isPinned = true
        let store = makeStoreLoadedWith([
            makeTextItem("match normal"),
            matchingPinned,
            unrelatedPinned,
        ])
        let viewModel = ClipboardPanelViewModel(store: store, settings: settings)

        viewModel.searchText = "match"

        XCTAssertEqual(viewModel.pinnedItems.map(\.title), ["match pinned"])
        XCTAssertEqual(viewModel.unpinnedItems.map(\.title), ["match normal"])
    }

    func testPinnedAndUnpinnedRowsPreserveFilteredIndices() {
        var pinned = makeTextItem("pinned")
        pinned.isPinned = true
        let store = makeStoreLoadedWith([
            makeTextItem(
                "first",
                createdAt: Date(timeIntervalSince1970: 1),
                lastCopiedAt: Date(timeIntervalSince1970: 1)
            ),
            pinned,
            makeTextItem(
                "third",
                createdAt: Date(timeIntervalSince1970: 3),
                lastCopiedAt: Date(timeIntervalSince1970: 3)
            ),
        ])
        let viewModel = ClipboardPanelViewModel(store: store, settings: settings)

        XCTAssertEqual(viewModel.filteredItems.map(\.title), ["pinned", "third", "first"])
        XCTAssertEqual(viewModel.pinnedRows.map(\.filteredIndex), [0])
        XCTAssertEqual(viewModel.pinnedRows.map(\.item.title), ["pinned"])
        XCTAssertEqual(viewModel.unpinnedRows.map(\.filteredIndex), [1, 2])
        XCTAssertEqual(viewModel.unpinnedRows.map(\.item.title), ["third", "first"])
    }

    func testFilteredRowIDsIncludeIndexToAvoidViewReuseForDuplicateItemIDs() {
        let sharedID = UUID()
        let store = makeStoreLoadedWith([
            makeTextItem("first", id: sharedID),
            makeTextItem("second", id: sharedID),
        ])
        let viewModel = ClipboardPanelViewModel(store: store, settings: settings)

        XCTAssertEqual(viewModel.filteredRows.count, 2)
        XCTAssertEqual(Set(viewModel.filteredRows.map(\.id)).count, 2)
    }

    func testSelectedRowIDTracksSelectedFilteredRow() {
        let store = makeStoreLoadedWith([
            makeTextItem("first", createdAt: Date(timeIntervalSince1970: 1), lastCopiedAt: Date(timeIntervalSince1970: 1)),
            makeTextItem("second", createdAt: Date(timeIntervalSince1970: 2), lastCopiedAt: Date(timeIntervalSince1970: 2)),
        ])
        let viewModel = ClipboardPanelViewModel(store: store, settings: settings)

        viewModel.selectIndex(1, scroll: false)

        XCTAssertEqual(viewModel.selectedRowID, viewModel.filteredRows[1].id)
        XCTAssertEqual(viewModel.selectedItem?.title, "first")
    }

    func testSelectedPreviewMetadataUsesSourceApplicationNameAndCopyCount() throws {
        let firstCopiedAt = Date(timeIntervalSince1970: 10)
        let lastCopiedAt = Date(timeIntervalSince1970: 20)
        let store = makeStoreLoadedWith([
            makeTextItem(
                "Hello",
                source: "com.apple.TextEdit",
                sourceApplicationName: "TextEdit",
                createdAt: firstCopiedAt,
                lastCopiedAt: lastCopiedAt,
                copyCount: 4
            ),
        ])
        let viewModel = ClipboardPanelViewModel(store: store, settings: settings)

        let metadata = try XCTUnwrap(viewModel.selectedPreviewMetadata)

        XCTAssertEqual(metadata.sourceName, "TextEdit")
        XCTAssertEqual(metadata.firstCopiedAt, firstCopiedAt)
        XCTAssertEqual(metadata.lastCopiedAt, lastCopiedAt)
        XCTAssertEqual(metadata.copyCount, 4)
    }

    func testSelectedPreviewMetadataFallsBackToSourceBundleIdentifier() throws {
        let store = makeStoreLoadedWith([
            makeTextItem("Hello", source: "com.apple.TextEdit"),
        ])
        let viewModel = ClipboardPanelViewModel(store: store, settings: settings)

        let metadata = try XCTUnwrap(viewModel.selectedPreviewMetadata)

        XCTAssertEqual(metadata.sourceName, "com.apple.TextEdit")
    }

    func testSelectedPreviewMetadataIsNilWhenFilteredSelectionIsEmpty() {
        let store = makeStoreLoadedWith([
            makeTextItem("Hello"),
        ])
        let viewModel = ClipboardPanelViewModel(store: store, settings: settings)

        viewModel.searchText = "missing"

        XCTAssertNil(viewModel.selectedPreviewMetadata)
    }

    private func makeStoreLoadedWith(_ items: [ClipboardItem]) -> ClipboardHistoryStore {
        let encoder = JSONEncoder()
        let data = try! encoder.encode(items)
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try! data.write(to: historyURL)

        let store = ClipboardHistoryStore(storageURL: historyURL, assetStore: assetStore, settings: settings)
        store.load()
        return store
    }

    private func makeTextItem(
        _ value: String,
        id: UUID = UUID(),
        preview: String? = nil,
        source: String? = "test.app",
        sourceApplicationName: String? = nil,
        createdAt: Date = Date(timeIntervalSince1970: 1),
        lastCopiedAt: Date = Date(timeIntervalSince1970: 1),
        copyCount: Int = 1
    ) -> ClipboardItem {
        ClipboardItem(
            id: id,
            title: value,
            createdAt: createdAt,
            lastCopiedAt: lastCopiedAt,
            copyCount: copyCount,
            contents: [
                ClipboardContent(
                    type: "public.utf8-plain-text",
                    storage: .inlineText(value),
                    previewText: preview ?? value
                ),
            ],
            sourceBundleIdentifier: source,
            sourceApplicationName: sourceApplicationName
        )
    }

    private func makeRichTextItem(
        _ title: String,
        plainText: String,
        richData: Data
    ) -> ClipboardItem {
        ClipboardItem(
            title: title,
            createdAt: Date(timeIntervalSince1970: 1),
            lastCopiedAt: Date(timeIntervalSince1970: 1),
            contents: [
                ClipboardContent(
                    type: "public.utf8-plain-text",
                    storage: .inlineText(plainText),
                    previewText: plainText
                ),
                ClipboardContent(
                    type: "public.rtf",
                    storage: .inlineData(richData),
                    previewText: plainText
                ),
            ],
            sourceBundleIdentifier: "test.app"
        )
    }
}

private final class FakeClipboardPanelPasteboardWriter: ClipboardPasteboardWriting {
    var values: [String: Data] = [:]

    func clearContents() {
        values.removeAll()
    }

    @discardableResult
    func setData(_ data: Data, forType type: String) -> Bool {
        values[type] = data
        return true
    }
}

private final class FakeClipboardPanelPasteEventPoster: ClipboardPasteEventPosting {
    var pasteCount = 0

    func postPasteShortcut() {
        pasteCount += 1
    }
}
