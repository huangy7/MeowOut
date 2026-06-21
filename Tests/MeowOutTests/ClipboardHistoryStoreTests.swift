import XCTest
@testable import MeowOut

@MainActor
final class ClipboardHistoryStoreTests: XCTestCase {
    private var root: URL!
    private var historyURL: URL!
    private var assetStore: ClipboardAssetStore!
    private var settings: ClipboardHistorySettings!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ClipboardHistoryStoreTests-\(UUID().uuidString)", isDirectory: true)
        historyURL = root.appendingPathComponent("clipboard-history.json")
        assetStore = ClipboardAssetStore(rootDirectory: root.appendingPathComponent("Assets", isDirectory: true))
        suiteName = "ClipboardHistoryStoreTests-\(UUID().uuidString)"
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

    func testAddDuplicateUpdatesExistingItem() async throws {
        let store = ClipboardHistoryStore(storageURL: historyURL, assetStore: assetStore, settings: settings)
        let item = makeTextItem("same")

        store.add(item)
        store.add(makeTextItem("same"))

        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items[0].copyCount, 2)
    }

    func testAddDuplicateNormalizesEquivalentPlainTextTypes() {
        let store = ClipboardHistoryStore(storageURL: historyURL, assetStore: assetStore, settings: settings)
        let legacy = ClipboardItem(
            title: "same",
            contents: [
                ClipboardContent(type: "NSStringPboardType", storage: .inlineData(Data("same".utf8)), previewText: "same"),
            ],
            sourceBundleIdentifier: "test.app"
        )
        let modern = ClipboardItem(
            title: "same",
            contents: [
                ClipboardContent(type: "public.utf8-plain-text", storage: .inlineText("same"), previewText: "same"),
            ],
            sourceBundleIdentifier: "test.app"
        )

        store.add(legacy)
        store.add(modern)

        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items[0].copyCount, 2)
    }

    func testAddSupersedingDuplicateMergesIntoExistingItemAndPreservesMetadata() throws {
        let store = ClipboardHistoryStore(storageURL: historyURL, assetStore: assetStore, settings: settings)
        let originalID = UUID()
        let originalCreatedAt = Date(timeIntervalSince1970: 100)
        let original = ClipboardItem(
            id: originalID,
            title: "Original title",
            createdAt: originalCreatedAt,
            lastCopiedAt: Date(timeIntervalSince1970: 120),
            copyCount: 2,
            contents: [
                ClipboardContent(type: "public.utf8-plain-text", storage: .inlineText("same"), previewText: "same"),
            ],
            sourceBundleIdentifier: "com.example.original",
            sourceApplicationName: "Original App",
            sourceApplicationIconFileName: "original-icon.png",
            isPinned: true
        )
        let richer = ClipboardItem(
            title: "Richer title",
            contents: [
                ClipboardContent(type: "public.utf8-plain-text", storage: .inlineText("same"), previewText: "same"),
                ClipboardContent(type: "public.html", storage: .inlineText("<p>same</p>"), previewText: "same"),
            ],
            sourceBundleIdentifier: "com.example.richer",
            sourceApplicationName: "Richer App",
            sourceApplicationIconFileName: "richer-icon.png"
        )

        store.add(original)
        store.add(richer)

        XCTAssertEqual(store.items.count, 1)
        let merged = try XCTUnwrap(store.items.first)
        XCTAssertEqual(merged.id, originalID)
        XCTAssertEqual(merged.createdAt, originalCreatedAt)
        XCTAssertEqual(merged.copyCount, 3)
        XCTAssertTrue(merged.isPinned)
        XCTAssertEqual(merged.title, "Original title")
        XCTAssertEqual(merged.sourceBundleIdentifier, "com.example.original")
        XCTAssertEqual(merged.sourceApplicationName, "Original App")
        XCTAssertEqual(merged.sourceApplicationIconFileName, "original-icon.png")
        XCTAssertTrue(merged.contents.contains { $0.type == "public.html" })
    }

    func testExistingRicherDuplicateMergesPlainTextDowngrade() throws {
        let store = ClipboardHistoryStore(storageURL: historyURL, assetStore: assetStore, settings: settings)
        let richer = ClipboardItem(
            title: "Rich",
            contents: [
                ClipboardContent(type: "public.utf8-plain-text", storage: .inlineText("same"), previewText: "same"),
                ClipboardContent(type: "public.html", storage: .inlineData(Data("<p>same</p>".utf8)), previewText: "same"),
            ],
            sourceBundleIdentifier: "com.example.rich"
        )
        let plain = ClipboardItem(
            title: "Plain",
            contents: [
                ClipboardContent(type: "public.utf8-plain-text", storage: .inlineText("same"), previewText: "same"),
            ],
            sourceBundleIdentifier: "com.example.plain"
        )

        store.add(richer)
        store.add(plain)

        XCTAssertEqual(store.items.count, 1)
        let merged = try XCTUnwrap(store.items.first)
        XCTAssertEqual(merged.copyCount, 2)
        XCTAssertEqual(merged.title, "Rich")
        XCTAssertTrue(merged.contents.contains { $0.type == "public.html" })
    }

    func testMergePreservesSourceMetadataAsAGroup() throws {
        let store = ClipboardHistoryStore(storageURL: historyURL, assetStore: assetStore, settings: settings)
        let old = ClipboardItem(
            title: "Old",
            contents: [
                ClipboardContent(type: "public.utf8-plain-text", storage: .inlineText("same"), previewText: "same"),
            ],
            sourceBundleIdentifier: "com.example.old"
        )
        let new = ClipboardItem(
            title: "New",
            contents: [
                ClipboardContent(type: "public.utf8-plain-text", storage: .inlineText("same"), previewText: "same"),
                ClipboardContent(type: "public.html", storage: .inlineData(Data("<p>same</p>".utf8)), previewText: "same"),
            ],
            sourceBundleIdentifier: "com.example.new",
            sourceApplicationName: "New App",
            sourceApplicationIconFileName: "new-icon.png"
        )

        store.add(old)
        store.add(new)

        let merged = try XCTUnwrap(store.items.first)
        XCTAssertEqual(merged.sourceBundleIdentifier, "com.example.old")
        XCTAssertNil(merged.sourceApplicationName)
        XCTAssertNil(merged.sourceApplicationIconFileName)
    }

    func testCapacityCleanupKeepsPinnedItems() async throws {
        settings.historyLimit = 2
        let store = ClipboardHistoryStore(storageURL: historyURL, assetStore: assetStore, settings: settings)
        var pinned = makeTextItem("pinned")
        pinned.isPinned = true

        store.add(pinned)
        store.add(makeTextItem("one"))
        store.add(makeTextItem("two"))
        store.add(makeTextItem("three"))

        XCTAssertTrue(store.items.contains(where: { $0.title == "pinned" && $0.isPinned }))
        XCTAssertEqual(store.items.filter { !$0.isPinned }.count, 2)
        XCTAssertFalse(store.items.contains(where: { $0.title == "one" }))
    }

    func testClearUnpinnedPreservesPinned() {
        let store = ClipboardHistoryStore(storageURL: historyURL, assetStore: assetStore, settings: settings)
        var pinned = makeTextItem("pinned")
        pinned.isPinned = true
        store.add(pinned)
        store.add(makeTextItem("temporary"))

        store.clearUnpinned()

        XCTAssertEqual(store.items.map(\.title), ["pinned"])
    }

    func testClearAllRemovesPinnedAndUnpinned() {
        let store = ClipboardHistoryStore(storageURL: historyURL, assetStore: assetStore, settings: settings)
        var pinned = makeTextItem("pinned")
        pinned.isPinned = true
        store.add(pinned)
        store.add(makeTextItem("temporary"))

        store.clearAll()

        XCTAssertTrue(store.items.isEmpty)
    }

    func testDeleteRemovesItemAndAssociatedAssetFile() throws {
        let fileName = try assetStore.write(Data([1, 2, 3]), preferredExtension: "bin")
        let item = makeAssetItem(title: "asset", fileName: fileName)
        let store = ClipboardHistoryStore(storageURL: historyURL, assetStore: assetStore, settings: settings)

        store.add(item)
        store.delete(item.id)

        XCTAssertTrue(store.items.isEmpty)
        XCTAssertThrowsError(try assetStore.read(fileName: fileName))
    }

    func testDuplicateAssetReplacementDeletesOldUnreferencedAssetFile() throws {
        let oldFileName = try assetStore.write(Data([1, 2, 3]), preferredExtension: "bin")
        let newFileName = try assetStore.write(Data([4, 5, 6]), preferredExtension: "bin")
        let store = ClipboardHistoryStore(storageURL: historyURL, assetStore: assetStore, settings: settings)

        store.add(makeDuplicateAssetItem(title: "old", fileName: oldFileName))
        store.add(makeDuplicateAssetItem(title: "new", fileName: newFileName))

        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items[0].title, "old")
        XCTAssertThrowsError(try assetStore.read(fileName: oldFileName))
        XCTAssertEqual(try assetStore.read(fileName: newFileName), Data([4, 5, 6]))
    }

    func testDuplicateMergeDeletesUnretainedSourceIconAssetFile() throws {
        let oldIconFileName = try assetStore.write(Data([1, 2, 3]), preferredExtension: "png")
        let newIconFileName = try assetStore.write(Data([4, 5, 6]), preferredExtension: "png")
        let store = ClipboardHistoryStore(storageURL: historyURL, assetStore: assetStore, settings: settings)

        store.add(
            makeTextItem(
                "same",
                sourceApplicationName: "Old App",
                sourceApplicationIconFileName: oldIconFileName
            )
        )
        store.add(
            makeTextItem(
                "same",
                sourceApplicationName: "New App",
                sourceApplicationIconFileName: newIconFileName
            )
        )

        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items[0].sourceApplicationIconFileName, oldIconFileName)
        XCTAssertEqual(try assetStore.read(fileName: oldIconFileName), Data([1, 2, 3]))
        XCTAssertThrowsError(try assetStore.read(fileName: newIconFileName))

        store.delete(store.items[0].id)

        XCTAssertThrowsError(try assetStore.read(fileName: oldIconFileName))
    }

    func testLoadPersistsAndReloadsItemsFromStorageURL() {
        let first = ClipboardHistoryStore(storageURL: historyURL, assetStore: assetStore, settings: settings)
        first.add(makeTextItem("persisted"))

        let second = ClipboardHistoryStore(storageURL: historyURL, assetStore: assetStore, settings: settings)
        second.load()

        XCTAssertEqual(second.items.map(\.title), ["persisted"])
    }

    func testLoadMergesExistingDuplicateItemsFromStorage() throws {
        var older = makeTextItem(
            "same",
            sourceApplicationName: "Original App",
            createdAt: Date(timeIntervalSince1970: 10),
            lastCopiedAt: Date(timeIntervalSince1970: 20),
            copyCount: 2
        )
        older.isPinned = true
        let newer = makeTextItem(
            "same",
            sourceApplicationName: "New App",
            createdAt: Date(timeIntervalSince1970: 30),
            lastCopiedAt: Date(timeIntervalSince1970: 40),
            copyCount: 3
        )
        let data = try JSONEncoder().encode([older, newer])
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try data.write(to: historyURL)

        let store = ClipboardHistoryStore(storageURL: historyURL, assetStore: assetStore, settings: settings)

        XCTAssertEqual(store.items.count, 1)
        let merged = try XCTUnwrap(store.items.first)
        XCTAssertEqual(merged.copyCount, 5)
        XCTAssertEqual(merged.createdAt, Date(timeIntervalSince1970: 10))
        XCTAssertEqual(merged.lastCopiedAt, Date(timeIntervalSince1970: 40))
        XCTAssertTrue(merged.isPinned)
        XCTAssertEqual(merged.sourceApplicationName, "Original App")
    }

    func testLoadDecodesItemsMissingSourceApplicationFields() throws {
        let item = makeTextItem("legacy", source: "com.example.legacy")
        let data = try JSONEncoder().encode([item])
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        json[0].removeValue(forKey: "sourceApplicationName")
        json[0].removeValue(forKey: "sourceApplicationIconFileName")
        let legacyData = try JSONSerialization.data(withJSONObject: json)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try legacyData.write(to: historyURL)

        let store = ClipboardHistoryStore(storageURL: historyURL, assetStore: assetStore, settings: settings)
        store.load()

        let loaded = try XCTUnwrap(store.items.first)
        XCTAssertEqual(loaded.title, "legacy")
        XCTAssertEqual(loaded.sourceBundleIdentifier, "com.example.legacy")
        XCTAssertNil(loaded.sourceApplicationName)
        XCTAssertNil(loaded.sourceApplicationIconFileName)
    }

    func testCorruptJSONIsBackedUpAndStoreStartsEmpty() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: historyURL)

        let store = ClipboardHistoryStore(storageURL: historyURL, assetStore: assetStore, settings: settings)
        store.load()

        let files = try FileManager.default.contentsOfDirectory(atPath: root.path)
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: historyURL.path))
        XCTAssertTrue(files.contains(where: { $0.contains("corrupt") && $0.hasSuffix(".json") }))
    }

    func testCorruptBackupsDoNotOverwriteEachOtherOnQuickSuccession() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        try Data("first corrupt".utf8).write(to: historyURL)
        let firstStore = ClipboardHistoryStore(storageURL: historyURL, assetStore: assetStore, settings: settings)
        firstStore.load()

        try Data("second corrupt".utf8).write(to: historyURL)
        let secondStore = ClipboardHistoryStore(storageURL: historyURL, assetStore: assetStore, settings: settings)
        secondStore.load()

        let backupURLs = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        )
        .filter { $0.lastPathComponent.contains("corrupt") && $0.pathExtension == "json" }

        let backupContents = try Set(backupURLs.map { try String(contentsOf: $0, encoding: .utf8) })
        XCTAssertEqual(backupURLs.count, 2)
        XCTAssertEqual(backupContents, ["first corrupt", "second corrupt"])
    }

    func testCorruptBackupFailureDoesNotDeleteOriginalFile() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("still here".utf8).write(to: historyURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: root.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        }

        let store = ClipboardHistoryStore(storageURL: historyURL, assetStore: assetStore, settings: settings)

        XCTAssertTrue(store.items.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: historyURL.path))
        XCTAssertEqual(try String(contentsOf: historyURL, encoding: .utf8), "still here")
    }

    func testSearchMatchesTitlePrimaryPreviewSourceBundleIdentifierAndSourceApplicationName() {
        let store = ClipboardHistoryStore(storageURL: historyURL, assetStore: assetStore, settings: settings)
        store.add(makeTextItem("title match", preview: "preview text", source: "com.example.source", sourceApplicationName: "Source App"))
        store.add(makeTextItem("other", preview: "Needle preview", source: "com.example.other"))
        store.add(makeTextItem("bundle", preview: "plain", source: "com.needle.app"))
        store.add(makeTextItem("application", preview: "plain", source: "com.example.application", sourceApplicationName: "Needle Writer"))

        XCTAssertEqual(Set(store.search("title").map(\.title)), ["title match"])
        XCTAssertEqual(Set(store.search("needle").map(\.title)), ["other", "bundle", "application"])
        XCTAssertEqual(store.search("SOURCE").map(\.title), ["title match"])
    }

    func testSortModeLastCopiedAtDefaultsToNewestFirst() {
        let old = makeTextItem("old", createdAt: Date(timeIntervalSince1970: 1), lastCopiedAt: Date(timeIntervalSince1970: 10))
        let new = makeTextItem("new", createdAt: Date(timeIntervalSince1970: 2), lastCopiedAt: Date(timeIntervalSince1970: 20))
        let store = makeStoreLoadedWith([old, new])

        XCTAssertEqual(store.items.map(\.title), ["new", "old"])
    }

    func testSortModeCopyCountSortsHighestFirst() {
        settings.sortMode = .copyCount
        let low = makeTextItem("low", copyCount: 1)
        let high = makeTextItem("high", copyCount: 3)
        let store = makeStoreLoadedWith([low, high])

        XCTAssertEqual(store.items.map(\.title), ["high", "low"])
    }

    func testSortModeCreatedAtSortsNewestFirst() {
        settings.sortMode = .createdAt
        let old = makeTextItem("old", createdAt: Date(timeIntervalSince1970: 1))
        let new = makeTextItem("new", createdAt: Date(timeIntervalSince1970: 2))
        let store = makeStoreLoadedWith([old, new])

        XCTAssertEqual(store.items.map(\.title), ["new", "old"])
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
        preview: String? = nil,
        source: String? = "test.app",
        sourceApplicationName: String? = nil,
        sourceApplicationIconFileName: String? = nil,
        createdAt: Date = Date(),
        lastCopiedAt: Date = Date(),
        copyCount: Int = 1
    ) -> ClipboardItem {
        ClipboardItem(
            title: value,
            createdAt: createdAt,
            lastCopiedAt: lastCopiedAt,
            copyCount: copyCount,
            contents: [ClipboardContent(type: "public.utf8-plain-text", storage: .inlineText(value), previewText: preview ?? value)],
            sourceBundleIdentifier: source,
            sourceApplicationName: sourceApplicationName,
            sourceApplicationIconFileName: sourceApplicationIconFileName
        )
    }

    private func makeAssetItem(title: String, fileName: String) -> ClipboardItem {
        ClipboardItem(
            title: title,
            contents: [ClipboardContent(type: "public.png", storage: .asset(fileName: fileName), previewText: title)],
            sourceBundleIdentifier: "test.app"
        )
    }

    private func makeDuplicateAssetItem(title: String, fileName: String) -> ClipboardItem {
        ClipboardItem(
            title: title,
            contents: [
                ClipboardContent(type: ClipboardContent.internalMarkerType, storage: .asset(fileName: fileName), previewText: nil),
                ClipboardContent(type: "public.utf8-plain-text", storage: .inlineText("same"), previewText: "same"),
            ],
            sourceBundleIdentifier: "test.app"
        )
    }
}
