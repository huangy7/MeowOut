import XCTest
@testable import MeowOut

final class ClipboardItemTests: XCTestCase {
    func testTextItemPreviewAndCodable() throws {
        let content = ClipboardContent(type: "public.utf8-plain-text", storage: .inlineText("hello world"), previewText: "hello world")
        let item = ClipboardItem(title: "hello world", contents: [content], sourceBundleIdentifier: "com.apple.TextEdit")

        XCTAssertEqual(item.primaryPreview, "hello world")
        XCTAssertEqual(item.primaryKind, .text)

        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(ClipboardItem.self, from: data)

        XCTAssertEqual(decoded.id, item.id)
        XCTAssertEqual(decoded.contents.first?.previewText, "hello world")
    }

    func testDuplicateComparisonIgnoresInternalMarker() {
        let text = ClipboardContent(type: "public.utf8-plain-text", storage: .inlineText("same"), previewText: "same")
        let marker = ClipboardContent(type: ClipboardContent.internalMarkerType, storage: .inlineData(Data()), previewText: nil)
        let lhs = ClipboardItem(title: "same", contents: [text, marker], sourceBundleIdentifier: nil)
        let rhs = ClipboardItem(title: "same", contents: [text], sourceBundleIdentifier: nil)

        XCTAssertTrue(lhs.hasSameEffectiveContents(as: rhs))
    }

    func testTextDuplicateComparisonNormalizesEquivalentPlainTextTypes() {
        let modern = ClipboardItem(
            title: "same",
            contents: [
                ClipboardContent(type: "public.utf8-plain-text", storage: .inlineText("same"), previewText: "same"),
            ],
            sourceBundleIdentifier: nil
        )
        let legacy = ClipboardItem(
            title: "same",
            contents: [
                ClipboardContent(type: "NSStringPboardType", storage: .inlineData(Data("same".utf8)), previewText: "same"),
            ],
            sourceBundleIdentifier: nil
        )
        let publicText = ClipboardItem(
            title: "same",
            contents: [
                ClipboardContent(type: "public.text", storage: .inlineText("same"), previewText: "same"),
            ],
            sourceBundleIdentifier: nil
        )

        XCTAssertTrue(modern.hasSameEffectiveContents(as: legacy))
        XCTAssertTrue(legacy.hasSameEffectiveContents(as: publicText))
        XCTAssertTrue(publicText.hasSameEffectiveContents(as: modern))
    }

    func testItemSupersedesWhenItContainsAllStableRepresentations() {
        let old = ClipboardItem(
            title: "Hello",
            contents: [
                ClipboardContent(type: "public.utf8-plain-text", storage: .inlineText("Hello"), previewText: "Hello"),
            ],
            sourceBundleIdentifier: "com.example.Old"
        )
        let new = ClipboardItem(
            title: "Hello",
            contents: [
                ClipboardContent(type: "public.utf8-plain-text", storage: .inlineText("Hello"), previewText: "Hello"),
                ClipboardContent(type: "public.html", storage: .inlineData(Data("<b>Hello</b>".utf8)), previewText: "Hello"),
            ],
            sourceBundleIdentifier: "com.example.New"
        )

        XCTAssertTrue(new.supersedes(old))
        XCTAssertFalse(old.supersedes(new))
        XCTAssertFalse(new.hasSameEffectiveContents(as: old))
    }

    func testTransientTypesAreIgnoredForDuplicateComparison() {
        let stable = ClipboardContent(type: "public.utf8-plain-text", storage: .inlineText("Hello"), previewText: "Hello")
        let old = ClipboardItem(
            title: "Hello",
            contents: [
                stable,
                ClipboardContent(type: "com.apple.WebKit.custom-pasteboard-data", storage: .inlineData(Data("old".utf8))),
            ],
            sourceBundleIdentifier: nil
        )
        let new = ClipboardItem(
            title: "Hello",
            contents: [
                stable,
                ClipboardContent(type: "com.apple.WebKit.custom-pasteboard-data", storage: .inlineData(Data("new".utf8))),
            ],
            sourceBundleIdentifier: nil
        )

        XCTAssertTrue(new.supersedes(old))
        XCTAssertTrue(old.supersedes(new))
        XCTAssertTrue(new.hasSameEffectiveContents(as: old))
    }

    func testDynamicAndMicrosoftOleSourceTypesAreIgnoredForDuplicateComparison() {
        let stable = ClipboardContent(type: "public.utf8-plain-text", storage: .inlineText("Hello"), previewText: "Hello")
        let old = ClipboardItem(
            title: "Hello",
            contents: [
                stable,
                ClipboardContent(type: "dyn.agq80w5xcq7g", storage: .inlineData(Data("old".utf8))),
            ],
            sourceBundleIdentifier: nil
        )
        let new = ClipboardItem(
            title: "Hello",
            contents: [
                stable,
                ClipboardContent(type: "com.microsoft.ole.source.SomeApp", storage: .inlineData(Data("new".utf8))),
            ],
            sourceBundleIdentifier: nil
        )

        XCTAssertTrue(new.supersedes(old))
        XCTAssertTrue(old.supersedes(new))
        XCTAssertTrue(new.hasSameEffectiveContents(as: old))
    }

    func testItemDoesNotSupersedeWhenOnlyTransientContentIsPresent() {
        let old = ClipboardItem(
            title: "metadata",
            contents: [
                ClipboardContent(type: "org.p0deje.Maccy", storage: .inlineData(Data("old".utf8))),
            ],
            sourceBundleIdentifier: nil
        )
        let new = ClipboardItem(
            title: "metadata",
            contents: [
                ClipboardContent(type: "org.p0deje.Maccy", storage: .inlineData(Data("new".utf8))),
            ],
            sourceBundleIdentifier: nil
        )

        XCTAssertFalse(new.supersedes(old))
        XCTAssertFalse(old.supersedes(new))
        XCTAssertFalse(new.hasSameEffectiveContents(as: old))
    }

    func testStableContentDoesNotSupersedeTransientOnlyContent() {
        let stable = ClipboardItem(
            title: "Hello",
            contents: [
                ClipboardContent(type: "public.utf8-plain-text", storage: .inlineText("Hello"), previewText: "Hello"),
            ],
            sourceBundleIdentifier: nil
        )
        let transientOnly = ClipboardItem(
            title: "metadata",
            contents: [
                ClipboardContent(type: "org.p0deje.Maccy", storage: .inlineData(Data("metadata".utf8))),
            ],
            sourceBundleIdentifier: nil
        )

        XCTAssertFalse(stable.supersedes(transientOnly))
        XCTAssertFalse(transientOnly.supersedes(stable))
        XCTAssertFalse(stable.hasSameEffectiveContents(as: transientOnly))
    }

    func testMultipleUnknownContentsReturnUnknownPrimaryKind() {
        let first = ClipboardContent(type: "com.example.custom-a", storage: .inlineData(Data([1])), previewText: nil)
        let second = ClipboardContent(type: "com.example.custom-b", storage: .inlineData(Data([2])), previewText: nil)
        let item = ClipboardItem(title: "custom", contents: [first, second], sourceBundleIdentifier: nil)

        XCTAssertEqual(item.primaryKind, .unknown)
    }

    func testAssetStoreWritesReadsAndDeletesData() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ClipboardAssetStoreTests-\(UUID().uuidString)", isDirectory: true)
        let store = ClipboardAssetStore(rootDirectory: root)
        let payload = Data([1, 2, 3, 4])

        let name = try store.write(payload, preferredExtension: "bin")
        XCTAssertEqual(try store.read(fileName: name), payload)

        try store.delete(fileName: name)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(name).path))
    }

    func testAssetStoreRejectsParentDirectoryRead() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ClipboardAssetStoreTests-\(UUID().uuidString)", isDirectory: true)
        let store = ClipboardAssetStore(rootDirectory: root)

        XCTAssertThrowsError(try store.read(fileName: "../escape.bin"))
    }

    func testAssetStoreRejectsAbsoluteDelete() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ClipboardAssetStoreTests-\(UUID().uuidString)", isDirectory: true)
        let store = ClipboardAssetStore(rootDirectory: root)

        XCTAssertThrowsError(try store.delete(fileName: "/tmp/escape.bin"))
    }

    func testAssetStoreFallsBackForUnsafePreferredExtension() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ClipboardAssetStoreTests-\(UUID().uuidString)", isDirectory: true)
        let store = ClipboardAssetStore(rootDirectory: root)
        let payload = Data([1, 2, 3, 4])

        let name = try store.write(payload, preferredExtension: "../png")

        XCTAssertTrue(name.hasSuffix(".bin"))
    }
}
