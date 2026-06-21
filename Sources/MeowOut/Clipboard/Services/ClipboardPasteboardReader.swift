import AppKit
import Foundation

public struct ClipboardPasteboardSnapshot: Sendable {
    public let changeCount: Int
    public let items: [ClipboardPasteboardSnapshotItem]
    public let sourceBundleIdentifier: String?
    public let sourceApplicationName: String?

    public init(
        changeCount: Int,
        items: [ClipboardPasteboardSnapshotItem],
        sourceBundleIdentifier: String?,
        sourceApplicationName: String? = nil
    ) {
        self.changeCount = changeCount
        self.items = items
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.sourceApplicationName = sourceApplicationName
    }
}

public struct ClipboardPasteboardSnapshotItem: Sendable {
    static let supportedContentTypes: Set<String> = [
        "public.utf8-plain-text",
        "NSStringPboardType",
        "public.text",
        "public.rtf",
        "public.html",
        "public.png",
        "public.tiff",
        "public.jpeg",
        "public.heic",
        "com.compuserve.gif",
        "public.file-url",
    ]

    public let types: [String]
    public let values: [String: Data]

    public init(types: [String], values: [String: Data]) {
        self.types = types
        self.values = values
    }
}

public protocol ClipboardPasteboardReading: AnyObject {
    var changeCount: Int { get }

    func snapshot() -> ClipboardPasteboardSnapshot
}

public final class NSPasteboardClipboardReader: ClipboardPasteboardReading {
    private let pasteboard: NSPasteboard

    public init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    public var changeCount: Int {
        pasteboard.changeCount
    }

    public func snapshot() -> ClipboardPasteboardSnapshot {
        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        let items: [ClipboardPasteboardSnapshotItem] = pasteboard.pasteboardItems?.map { pasteboardItem in
            let types = pasteboardItem.types.map(\.rawValue)
            let values = Dictionary(
                uniqueKeysWithValues: pasteboardItem.types.compactMap { type -> (String, Data)? in
                    guard ClipboardPasteboardSnapshotItem.supportedContentTypes.contains(type.rawValue) else {
                        return nil
                    }

                    return pasteboardItem.data(forType: type).map { (type.rawValue, $0) }
                }
            )

            return ClipboardPasteboardSnapshotItem(types: types, values: values)
        } ?? []

        return ClipboardPasteboardSnapshot(
            changeCount: pasteboard.changeCount,
            items: items,
            // NSPasteboard does not expose the writer process. This approximates the
            // source as the frontmost app at poll time for Task 4 ignored-app filtering.
            sourceBundleIdentifier: frontmostApplication?.bundleIdentifier,
            sourceApplicationName: frontmostApplication?.localizedName
        )
    }
}
