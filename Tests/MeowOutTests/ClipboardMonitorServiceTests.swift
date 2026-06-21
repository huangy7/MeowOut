import AppKit
import Foundation
import XCTest
@testable import MeowOut

@MainActor
final class ClipboardMonitorServiceTests: XCTestCase {
    func testMonitorInitializationReadsChangeCountWithoutSnapshot() {
        let harness = MonitorHarness()

        XCTAssertEqual(harness.reader.changeCountReadCount, 1)
        XCTAssertEqual(harness.reader.snapshotCallCount, 0)
    }

    func testRecordsExternalTextCopy() {
        let harness = MonitorHarness()
        harness.reader.changeCount = 2
        harness.reader.items = [
            ClipboardPasteboardSnapshotItem(types: ["public.utf8-plain-text"], values: ["public.utf8-plain-text": Data("hello".utf8)])
        ]

        harness.monitor.checkNow()

        XCTAssertEqual(harness.store.items.count, 1)
        XCTAssertEqual(harness.store.items[0].primaryPreview, "hello")
    }

    func testRecordsSourceApplicationMetadata() {
        let harness = MonitorHarness()
        harness.reader.changeCount = 2
        harness.reader.sourceBundleIdentifier = "com.apple.TextEdit"
        harness.reader.sourceApplicationName = "TextEdit"
        harness.reader.items = [
            ClipboardPasteboardSnapshotItem(types: ["public.utf8-plain-text"], values: ["public.utf8-plain-text": Data("hello".utf8)])
        ]

        harness.monitor.checkNow()

        XCTAssertEqual(harness.store.items.count, 1)
        XCTAssertEqual(harness.store.items[0].sourceBundleIdentifier, "com.apple.TextEdit")
        XCTAssertEqual(harness.store.items[0].sourceApplicationName, "TextEdit")
    }

    func testSkipsInternalMarker() {
        let harness = MonitorHarness()
        harness.reader.changeCount = 2
        harness.reader.items = [
            ClipboardPasteboardSnapshotItem(types: [ClipboardContent.internalMarkerType], values: [ClipboardContent.internalMarkerType: Data()])
        ]

        harness.monitor.checkNow()

        XCTAssertTrue(harness.store.items.isEmpty)
    }

    func testSkipsIgnoredType() {
        let harness = MonitorHarness()
        harness.reader.changeCount = 2
        harness.reader.items = [
            ClipboardPasteboardSnapshotItem(types: ["org.nspasteboard.ConcealedType", "public.utf8-plain-text"], values: ["public.utf8-plain-text": Data("secret".utf8)])
        ]

        harness.monitor.checkNow()

        XCTAssertTrue(harness.store.items.isEmpty)
    }

    func testDoesNothingWhenChangeCountIsUnchanged() {
        let harness = MonitorHarness()
        harness.reader.items = [
            ClipboardPasteboardSnapshotItem(types: ["public.utf8-plain-text"], values: ["public.utf8-plain-text": Data("hello".utf8)])
        ]

        harness.monitor.checkNow()

        XCTAssertTrue(harness.store.items.isEmpty)
        XCTAssertEqual(harness.reader.snapshotCallCount, 0)
    }

    func testDoesNothingWhenSettingsIsDisabled() {
        let harness = MonitorHarness()
        harness.settings.isEnabled = false
        harness.reader.changeCount = 2
        harness.reader.items = [
            ClipboardPasteboardSnapshotItem(types: ["public.utf8-plain-text"], values: ["public.utf8-plain-text": Data("hello".utf8)])
        ]

        harness.monitor.checkNow()

        XCTAssertTrue(harness.store.items.isEmpty)
    }

    func testStartSchedulesTimerWhenSettingsIsDisabled() {
        let harness = MonitorHarness()
        harness.settings.isEnabled = false
        harness.reader.changeCount = 2
        harness.reader.items = [
            ClipboardPasteboardSnapshotItem(types: ["public.utf8-plain-text"], values: ["public.utf8-plain-text": Data("hello".utf8)])
        ]

        harness.monitor.start()
        harness.settings.isEnabled = true
        RunLoop.current.run(until: Date().addingTimeInterval(0.7))
        harness.monitor.stop()

        XCTAssertEqual(harness.store.items.count, 1)
        XCTAssertEqual(harness.store.items.first?.primaryPreview, "hello")
    }

    func testSkipsIgnoredSourceApplicationBundleID() {
        let harness = MonitorHarness()
        harness.settings.ignoredApplications = ["test.source"]
        harness.reader.sourceBundleIdentifier = "test.source"
        harness.reader.changeCount = 2
        harness.reader.items = [
            ClipboardPasteboardSnapshotItem(types: ["public.utf8-plain-text"], values: ["public.utf8-plain-text": Data("hello".utf8)])
        ]

        harness.monitor.checkNow()

        XCTAssertTrue(harness.store.items.isEmpty)
    }

    func testSkipsBlankWhitespaceText() {
        let harness = MonitorHarness()
        harness.reader.changeCount = 2
        harness.reader.items = [
            ClipboardPasteboardSnapshotItem(types: ["public.utf8-plain-text"], values: ["public.utf8-plain-text": Data(" \n\t ".utf8)])
        ]

        harness.monitor.checkNow()

        XCTAssertTrue(harness.store.items.isEmpty)
    }

    func testRespectsRecordTextFalse() {
        let harness = MonitorHarness()
        harness.settings.recordText = false
        harness.reader.changeCount = 2
        harness.reader.items = [
            ClipboardPasteboardSnapshotItem(types: ["public.utf8-plain-text"], values: ["public.utf8-plain-text": Data("hello".utf8)])
        ]

        harness.monitor.checkNow()

        XCTAssertTrue(harness.store.items.isEmpty)
    }

    func testRecordTextFalseAlsoSkipsRichTextRepresentations() {
        let harness = MonitorHarness()
        harness.settings.recordText = false
        harness.reader.changeCount = 2
        harness.reader.items = [
            ClipboardPasteboardSnapshotItem(types: ["public.rtf", "public.html"], values: [
                "public.rtf": Data("{\\rtf1 hello}".utf8),
                "public.html": Data("<p>hello</p>".utf8),
            ])
        ]

        harness.monitor.checkNow()

        XCTAssertTrue(harness.store.items.isEmpty)
    }

    func testRichTextPreviewUsesPlainTextFromRTFData() throws {
        let harness = MonitorHarness()
        let attributedString = NSAttributedString(string: "hello rich text")
        let rtfData = try XCTUnwrap(
            attributedString.rtf(
                from: NSRange(location: 0, length: attributedString.length),
                documentAttributes: [:]
            )
        )
        harness.reader.changeCount = 2
        harness.reader.items = [
            ClipboardPasteboardSnapshotItem(types: ["public.rtf"], values: ["public.rtf": rtfData])
        ]

        harness.monitor.checkNow()

        XCTAssertEqual(harness.store.items.count, 1)
        XCTAssertEqual(harness.store.items[0].primaryPreview, "hello rich text")
    }

    func testRespectsRecordImagesFalse() {
        let harness = MonitorHarness()
        harness.settings.recordImages = false
        harness.reader.changeCount = 2
        harness.reader.items = [
            ClipboardPasteboardSnapshotItem(types: ["public.png", "public.tiff"], values: [
                "public.png": Data([0x89, 0x50, 0x4E, 0x47]),
                "public.tiff": Data([0x49, 0x49, 0x2A, 0x00]),
            ])
        ]

        harness.monitor.checkNow()

        XCTAssertTrue(harness.store.items.isEmpty)
    }

    func testRecordsCommonImagePasteboardTypes() {
        let harness = MonitorHarness()
        harness.reader.changeCount = 2
        harness.reader.items = [
            ClipboardPasteboardSnapshotItem(types: [
                "public.jpeg",
                "public.heic",
                "com.compuserve.gif",
            ], values: [
                "public.jpeg": Data([0xFF, 0xD8, 0xFF]),
                "public.heic": Data("heic".utf8),
                "com.compuserve.gif": Data("GIF89a".utf8),
            ])
        ]

        harness.monitor.checkNow()

        XCTAssertEqual(harness.store.items.count, 1)
        XCTAssertEqual(
            Set(harness.store.items[0].contents.map(\.type)),
            ["public.jpeg", "public.heic", "com.compuserve.gif"]
        )
        XCTAssertEqual(harness.store.items[0].primaryKind, .image)
    }

    func testRespectsRecordFilesFalse() {
        let harness = MonitorHarness()
        harness.settings.recordFiles = false
        harness.reader.changeCount = 2
        harness.reader.items = [
            ClipboardPasteboardSnapshotItem(types: ["public.file-url"], values: ["public.file-url": Data("file:///tmp/report.txt".utf8)])
        ]

        harness.monitor.checkNow()

        XCTAssertTrue(harness.store.items.isEmpty)
    }

    func testFiltersDynamicAndMicrosoftOLESourceTypes() {
        let harness = MonitorHarness()
        harness.reader.changeCount = 2
        harness.reader.items = [
            ClipboardPasteboardSnapshotItem(types: [
                "dyn.ah62d4rv4ge80g5pb",
                "com.microsoft.ole.source.Excel",
                "public.utf8-plain-text",
            ], values: [
                "dyn.ah62d4rv4ge80g5pb": Data([1, 2, 3]),
                "com.microsoft.ole.source.Excel": Data([4, 5, 6]),
                "public.utf8-plain-text": Data("hello".utf8),
            ])
        ]

        harness.monitor.checkNow()

        XCTAssertEqual(harness.store.items.count, 1)
        XCTAssertEqual(harness.store.items[0].contents.map(\.type), ["public.utf8-plain-text"])
    }

    func testUnsupportedPrivateTypeValuesAreNotRequiredByMonitor() {
        let harness = MonitorHarness()
        harness.reader.changeCount = 2
        harness.reader.items = [
            ClipboardPasteboardSnapshotItem(types: [
                "com.example.private-type",
                "com.microsoft.ole.sourceX",
                "public.utf8-plain-text",
            ], values: [
                "public.utf8-plain-text": Data("hello".utf8),
            ])
        ]

        harness.monitor.checkNow()

        XCTAssertEqual(harness.store.items.count, 1)
        XCTAssertEqual(harness.store.items[0].contents.map(\.type), ["public.utf8-plain-text"])
    }

    func testCombinesMultiplePasteboardItemsIntoOneClipboardItem() {
        let harness = MonitorHarness()
        harness.reader.changeCount = 2
        harness.reader.items = [
            ClipboardPasteboardSnapshotItem(types: ["public.utf8-plain-text"], values: ["public.utf8-plain-text": Data("hello".utf8)]),
            ClipboardPasteboardSnapshotItem(types: ["public.file-url"], values: ["public.file-url": Data("file:///tmp/report.txt".utf8)]),
        ]

        harness.monitor.checkNow()

        XCTAssertEqual(harness.store.items.count, 1)
        XCTAssertEqual(harness.store.items[0].contents.count, 2)
        XCTAssertEqual(harness.store.items[0].primaryPreview, "hello")
        XCTAssertEqual(harness.store.items[0].contents[1].fileNames, ["report.txt"])
    }
}

@MainActor
private final class MonitorHarness {
    let reader = FakeClipboardPasteboardReader()
    let store: ClipboardHistoryStore
    let settings: ClipboardHistorySettings
    let monitor: ClipboardMonitorService

    init() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MonitorHarness-\(UUID().uuidString)", isDirectory: true)
        settings = ClipboardHistorySettings(defaults: UserDefaults(suiteName: "MonitorHarness-\(UUID().uuidString)")!)
        store = ClipboardHistoryStore(
            storageURL: root.appendingPathComponent("history.json"),
            assetStore: ClipboardAssetStore(rootDirectory: root.appendingPathComponent("Assets", isDirectory: true)),
            settings: settings
        )
        monitor = ClipboardMonitorService(reader: reader, store: store, settings: settings)
    }
}

private final class FakeClipboardPasteboardReader: ClipboardPasteboardReading {
    private var storedChangeCount = 1
    private(set) var changeCountReadCount = 0
    private(set) var snapshotCallCount = 0
    var items: [ClipboardPasteboardSnapshotItem] = []
    var sourceBundleIdentifier: String? = "test.source"
    var sourceApplicationName: String?

    var changeCount: Int {
        get {
            changeCountReadCount += 1
            return storedChangeCount
        }
        set {
            storedChangeCount = newValue
        }
    }

    func snapshot() -> ClipboardPasteboardSnapshot {
        snapshotCallCount += 1
        return ClipboardPasteboardSnapshot(
            changeCount: storedChangeCount,
            items: items,
            sourceBundleIdentifier: sourceBundleIdentifier,
            sourceApplicationName: sourceApplicationName
        )
    }
}
