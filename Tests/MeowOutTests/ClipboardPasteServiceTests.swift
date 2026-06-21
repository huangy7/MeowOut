import Foundation
import XCTest
@testable import MeowOut

final class ClipboardPasteServiceTests: XCTestCase {
    func testWritesTextAndInternalMarker() {
        let writer = FakeClipboardPasteboardWriter()
        let service = ClipboardPasteService(writer: writer, eventPoster: FakePasteEventPoster())
        let item = ClipboardItem(
            title: "hello",
            contents: [ClipboardContent(type: "public.utf8-plain-text", storage: .inlineText("hello"), previewText: "hello")],
            sourceBundleIdentifier: nil
        )

        service.copy(item, removeFormatting: false, pasteAutomatically: false)

        XCTAssertEqual(writer.values["public.utf8-plain-text"], Data("hello".utf8))
        XCTAssertNotNil(writer.values[ClipboardContent.internalMarkerType])
    }

    func testAutomaticPastePostsPasteEvent() {
        let writer = FakeClipboardPasteboardWriter()
        let poster = FakePasteEventPoster()
        let notificationCenter = NotificationCenter()
        let service = ClipboardPasteService(
            writer: writer,
            eventPoster: poster,
            notificationCenter: notificationCenter,
            canPasteAutomatically: { true }
        )
        let item = ClipboardItem(
            title: "hello",
            contents: [ClipboardContent(type: "public.utf8-plain-text", storage: .inlineText("hello"), previewText: "hello")],
            sourceBundleIdentifier: nil
        )
        let expectation = expectation(
            forNotification: .clipboardHistoryDidPaste,
            object: nil,
            notificationCenter: notificationCenter
        )

        service.copy(item, removeFormatting: false, pasteAutomatically: true)

        wait(for: [expectation], timeout: 1)
        XCTAssertEqual(poster.pasteCount, 1)
    }

    func testClearContentsIsCalledBeforeWriting() {
        let writer = FakeClipboardPasteboardWriter()
        let service = ClipboardPasteService(writer: writer, eventPoster: FakePasteEventPoster())
        let item = ClipboardItem(
            title: "hello",
            contents: [ClipboardContent(type: "public.utf8-plain-text", storage: .inlineText("hello"), previewText: "hello")],
            sourceBundleIdentifier: nil
        )

        service.copy(item, removeFormatting: false, pasteAutomatically: false)

        XCTAssertEqual(writer.events.first, .clear)
        XCTAssertEqual(writer.events.dropFirst().first, .write("public.utf8-plain-text", Data("hello".utf8)))
    }

    func testWritesInlineDataContents() {
        let writer = FakeClipboardPasteboardWriter()
        let service = ClipboardPasteService(writer: writer, eventPoster: FakePasteEventPoster())
        let data = Data([0, 1, 2, 3])
        let item = ClipboardItem(
            title: "image",
            contents: [ClipboardContent(type: "public.png", storage: .inlineData(data), previewText: nil)],
            sourceBundleIdentifier: nil
        )

        service.copy(item, removeFormatting: false, pasteAutomatically: false)

        XCTAssertEqual(writer.values["public.png"], data)
    }

    func testWritesAssetContents() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardPasteServiceTests-\(UUID().uuidString)", isDirectory: true)
        let assetStore = ClipboardAssetStore(rootDirectory: root)
        let assetData = Data([4, 5, 6])
        let fileName = try assetStore.write(assetData, preferredExtension: "png")
        let writer = FakeClipboardPasteboardWriter()
        let service = ClipboardPasteService(
            writer: writer,
            eventPoster: FakePasteEventPoster(),
            assetStore: assetStore
        )
        let item = ClipboardItem(
            title: "image",
            contents: [ClipboardContent(type: "public.png", storage: .asset(fileName: fileName), previewText: nil)],
            sourceBundleIdentifier: nil
        )

        service.copy(item, removeFormatting: false, pasteAutomatically: false)

        XCTAssertEqual(writer.values["public.png"], assetData)
        try? FileManager.default.removeItem(at: root)
    }

    func testRemoveFormattingFalseWritesAllWritableContentsExceptInternalMarker() {
        let writer = FakeClipboardPasteboardWriter()
        let service = ClipboardPasteService(writer: writer, eventPoster: FakePasteEventPoster())
        let item = ClipboardItem(
            title: "mixed",
            contents: [
                ClipboardContent(type: "public.utf8-plain-text", storage: .inlineText("hello"), previewText: "hello"),
                ClipboardContent(type: "public.rtf", storage: .inlineData(Data([1, 2])), previewText: "hello"),
                ClipboardContent(type: ClipboardContent.internalMarkerType, storage: .inlineData(Data([9])), previewText: nil),
            ],
            sourceBundleIdentifier: nil
        )

        service.copy(item, removeFormatting: false, pasteAutomatically: false)

        XCTAssertEqual(writer.values["public.utf8-plain-text"], Data("hello".utf8))
        XCTAssertEqual(writer.values["public.rtf"], Data([1, 2]))
        XCTAssertEqual(writer.values[ClipboardContent.internalMarkerType], Data())
        let markerWrites = writer.events.filter { event in
            if case .write(ClipboardContent.internalMarkerType, _) = event {
                return true
            }
            return false
        }
        XCTAssertEqual(markerWrites, [.write(ClipboardContent.internalMarkerType, Data())])
    }

    func testRemoveFormattingTrueWithTextWritesOnlyTextContent() {
        let writer = FakeClipboardPasteboardWriter()
        let service = ClipboardPasteService(writer: writer, eventPoster: FakePasteEventPoster())
        let item = ClipboardItem(
            title: "rich",
            contents: [
                ClipboardContent(type: "public.utf8-plain-text", storage: .inlineText("hello"), previewText: "hello"),
                ClipboardContent(type: "public.rtf", storage: .inlineData(Data([1, 2])), previewText: "hello"),
            ],
            sourceBundleIdentifier: nil
        )

        service.copy(item, removeFormatting: true, pasteAutomatically: false)

        XCTAssertEqual(writer.values["public.utf8-plain-text"], Data("hello".utf8))
        XCTAssertNil(writer.values["public.rtf"])
        XCTAssertNotNil(writer.values[ClipboardContent.internalMarkerType])
    }

    func testRemoveFormattingTrueWithRichTextPreviewWritesPlainTextFallback() {
        let writer = FakeClipboardPasteboardWriter()
        let service = ClipboardPasteService(writer: writer, eventPoster: FakePasteEventPoster())
        let item = ClipboardItem(
            title: "rich",
            contents: [ClipboardContent(type: "public.rtf", storage: .inlineData(Data([1, 2])), previewText: "hello")],
            sourceBundleIdentifier: nil
        )

        service.copy(item, removeFormatting: true, pasteAutomatically: false)

        XCTAssertEqual(writer.values["public.utf8-plain-text"], Data("hello".utf8))
        XCTAssertNil(writer.values["public.rtf"])
        XCTAssertNotNil(writer.values[ClipboardContent.internalMarkerType])
    }

    func testRemoveFormattingTrueWithImageAndNoTextFallbackWritesNormalContents() {
        let writer = FakeClipboardPasteboardWriter()
        let service = ClipboardPasteService(writer: writer, eventPoster: FakePasteEventPoster())
        let imageData = Data([7, 8, 9])
        let item = ClipboardItem(
            title: "image",
            contents: [ClipboardContent(type: "public.png", storage: .inlineData(imageData), previewText: nil)],
            sourceBundleIdentifier: nil
        )

        service.copy(item, removeFormatting: true, pasteAutomatically: false)

        XCTAssertEqual(writer.values["public.png"], imageData)
        XCTAssertNotNil(writer.values[ClipboardContent.internalMarkerType])
    }

    func testInternalMarkerIsWrittenWhenPayloadContentCannotBeRead() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardPasteServiceTests-\(UUID().uuidString)", isDirectory: true)
        let writer = FakeClipboardPasteboardWriter()
        let service = ClipboardPasteService(
            writer: writer,
            eventPoster: FakePasteEventPoster(),
            assetStore: ClipboardAssetStore(rootDirectory: root)
        )
        let item = ClipboardItem(
            title: "missing",
            contents: [ClipboardContent(type: "public.png", storage: .asset(fileName: "missing.png"), previewText: nil)],
            sourceBundleIdentifier: nil
        )

        service.copy(item, removeFormatting: false, pasteAutomatically: false)

        XCTAssertNil(writer.values["public.png"])
        XCTAssertEqual(writer.values[ClipboardContent.internalMarkerType], Data())
    }

    func testPasteAutomaticallyFalseDoesNotCallEventPoster() {
        let poster = FakePasteEventPoster()
        let service = ClipboardPasteService(
            writer: FakeClipboardPasteboardWriter(),
            eventPoster: poster,
            canPasteAutomatically: { true }
        )
        let item = ClipboardItem(
            title: "hello",
            contents: [ClipboardContent(type: "public.utf8-plain-text", storage: .inlineText("hello"), previewText: "hello")],
            sourceBundleIdentifier: nil
        )

        service.copy(item, removeFormatting: false, pasteAutomatically: false)

        XCTAssertEqual(poster.pasteCount, 0)
    }

    func testPasteAutomaticallyWithoutPermissionPostsAccessibilityNotification() {
        let poster = FakePasteEventPoster()
        let notificationCenter = NotificationCenter()
        let service = ClipboardPasteService(
            writer: FakeClipboardPasteboardWriter(),
            eventPoster: poster,
            notificationCenter: notificationCenter,
            canPasteAutomatically: { false }
        )
        let item = ClipboardItem(
            title: "hello",
            contents: [ClipboardContent(type: "public.utf8-plain-text", storage: .inlineText("hello"), previewText: "hello")],
            sourceBundleIdentifier: nil
        )
        let expectation = expectation(
            forNotification: .clipboardHistoryRequireAccessibility,
            object: nil,
            notificationCenter: notificationCenter
        )

        service.copy(item, removeFormatting: false, pasteAutomatically: true)

        wait(for: [expectation], timeout: 1)
        XCTAssertEqual(poster.pasteCount, 0)
    }

    func testAutomaticPasteDoesNotPostWhenNoPayloadContentWasWritten() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardPasteServiceTests-\(UUID().uuidString)", isDirectory: true)
        let poster = FakePasteEventPoster()
        let notificationCenter = NotificationCenter()
        let service = ClipboardPasteService(
            writer: FakeClipboardPasteboardWriter(),
            eventPoster: poster,
            assetStore: ClipboardAssetStore(rootDirectory: root),
            notificationCenter: notificationCenter,
            canPasteAutomatically: { true }
        )
        let item = ClipboardItem(
            title: "missing",
            contents: [ClipboardContent(type: "public.png", storage: .asset(fileName: "missing.png"), previewText: nil)],
            sourceBundleIdentifier: nil
        )
        let invertedExpectation = expectation(
            forNotification: .clipboardHistoryDidPaste,
            object: nil,
            notificationCenter: notificationCenter
        )
        invertedExpectation.isInverted = true

        service.copy(item, removeFormatting: false, pasteAutomatically: true)

        wait(for: [invertedExpectation], timeout: 0.1)
        XCTAssertEqual(poster.pasteCount, 0)
    }

    func testAutomaticPasteDoesNotPostWhenPayloadWriteFails() {
        let writer = FakeClipboardPasteboardWriter()
        writer.failingTypes = ["public.utf8-plain-text"]
        let poster = FakePasteEventPoster()
        let notificationCenter = NotificationCenter()
        let service = ClipboardPasteService(
            writer: writer,
            eventPoster: poster,
            notificationCenter: notificationCenter,
            canPasteAutomatically: { true }
        )
        let item = ClipboardItem(
            title: "hello",
            contents: [ClipboardContent(type: "public.utf8-plain-text", storage: .inlineText("hello"), previewText: "hello")],
            sourceBundleIdentifier: nil
        )
        let invertedExpectation = expectation(
            forNotification: .clipboardHistoryDidPaste,
            object: nil,
            notificationCenter: notificationCenter
        )
        invertedExpectation.isInverted = true

        service.copy(item, removeFormatting: false, pasteAutomatically: true)

        wait(for: [invertedExpectation], timeout: 0.1)
        XCTAssertEqual(poster.pasteCount, 0)
        XCTAssertNil(writer.values["public.utf8-plain-text"])
        XCTAssertEqual(writer.values[ClipboardContent.internalMarkerType], Data())
    }

    func testAutomaticPasteDoesNotPostWhenInternalMarkerWriteFails() {
        let writer = FakeClipboardPasteboardWriter()
        writer.failingTypes = [ClipboardContent.internalMarkerType]
        let poster = FakePasteEventPoster()
        let notificationCenter = NotificationCenter()
        let service = ClipboardPasteService(
            writer: writer,
            eventPoster: poster,
            notificationCenter: notificationCenter,
            canPasteAutomatically: { true }
        )
        let item = ClipboardItem(
            title: "hello",
            contents: [ClipboardContent(type: "public.utf8-plain-text", storage: .inlineText("hello"), previewText: "hello")],
            sourceBundleIdentifier: nil
        )
        let invertedExpectation = expectation(
            forNotification: .clipboardHistoryDidPaste,
            object: nil,
            notificationCenter: notificationCenter
        )
        invertedExpectation.isInverted = true

        service.copy(item, removeFormatting: false, pasteAutomatically: true)

        wait(for: [invertedExpectation], timeout: 0.1)
        XCTAssertEqual(poster.pasteCount, 0)
        XCTAssertEqual(writer.values["public.utf8-plain-text"], Data("hello".utf8))
        XCTAssertNil(writer.values[ClipboardContent.internalMarkerType])
    }
}

private final class FakeClipboardPasteboardWriter: ClipboardPasteboardWriting {
    enum Event: Equatable {
        case clear
        case write(String, Data)
    }

    var values: [String: Data] = [:]
    var events: [Event] = []
    var failingTypes: Set<String> = []

    func clearContents() {
        events.append(.clear)
        values.removeAll()
    }

    @discardableResult
    func setData(_ data: Data, forType type: String) -> Bool {
        guard !failingTypes.contains(type) else {
            return false
        }

        events.append(.write(type, data))
        values[type] = data
        return true
    }
}

private final class FakePasteEventPoster: ClipboardPasteEventPosting {
    var pasteCount = 0

    func postPasteShortcut() {
        pasteCount += 1
    }
}
