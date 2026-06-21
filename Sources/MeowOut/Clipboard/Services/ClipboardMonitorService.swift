import AppKit
import Foundation

@MainActor
public final class ClipboardMonitorService {
    public static let shared = ClipboardMonitorService()

    private let reader: ClipboardPasteboardReading
    private let store: ClipboardHistoryStore
    private let settings: ClipboardHistorySettings
    private let assetStore: ClipboardAssetStore
    private var timer: Timer?
    private var lastChangeCount: Int

    public convenience init(
        reader: ClipboardPasteboardReading = NSPasteboardClipboardReader(),
        store: ClipboardHistoryStore? = nil,
        settings: ClipboardHistorySettings? = nil,
        assetStore: ClipboardAssetStore = .applicationSupportStore
    ) {
        self.init(
            reader: reader,
            store: store ?? .shared,
            settings: settings ?? .shared,
            assetStore: assetStore,
            lastChangeCount: reader.changeCount
        )
    }

    private init(
        reader: ClipboardPasteboardReading,
        store: ClipboardHistoryStore,
        settings: ClipboardHistorySettings,
        assetStore: ClipboardAssetStore,
        lastChangeCount: Int
    ) {
        self.reader = reader
        self.store = store
        self.settings = settings
        self.assetStore = assetStore
        self.lastChangeCount = lastChangeCount
    }

    deinit {
        timer?.invalidate()
    }

    public func start() {
        stop()

        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkNow()
            }
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    public func restart() {
        stop()
        start()
    }

    public func checkNow() {
        let currentChangeCount = reader.changeCount
        guard currentChangeCount != lastChangeCount else {
            return
        }

        let snapshot = reader.snapshot()
        lastChangeCount = snapshot.changeCount

        guard settings.isEnabled,
              !containsInternalMarker(in: snapshot),
              !containsIgnoredPasteboardType(in: snapshot),
              !isIgnoredApplication(snapshot.sourceBundleIdentifier)
        else {
            return
        }

        let contents = snapshot.items.flatMap(contents(from:))
        guard !contents.isEmpty else {
            return
        }

        store.add(
            ClipboardItem(
                title: title(for: contents),
                contents: contents,
                sourceBundleIdentifier: snapshot.sourceBundleIdentifier,
                sourceApplicationName: snapshot.sourceApplicationName
            )
        )
    }

    private func containsInternalMarker(in snapshot: ClipboardPasteboardSnapshot) -> Bool {
        snapshot.items.contains { item in
            item.types.contains(ClipboardContent.internalMarkerType)
        }
    }

    private func containsIgnoredPasteboardType(in snapshot: ClipboardPasteboardSnapshot) -> Bool {
        let ignoredTypes = settings.ignoredPasteboardTypes
        return snapshot.items.contains { item in
            !ignoredTypes.isDisjoint(with: item.types)
        }
    }

    private func isIgnoredApplication(_ bundleIdentifier: String?) -> Bool {
        // The concrete reader approximates this as the frontmost app at poll time,
        // because NSPasteboard does not provide the original writer application.
        guard let bundleIdentifier else {
            return false
        }

        return settings.ignoredApplications.contains(bundleIdentifier)
    }

    private func contents(from item: ClipboardPasteboardSnapshotItem) -> [ClipboardContent] {
        item.types.compactMap { type in
            guard !isFilteredType(type),
                  let data = item.values[type]
            else {
                return nil
            }

            switch type {
            case "public.utf8-plain-text", "NSStringPboardType", "public.text":
                return textContent(type: type, data: data)
            case "public.rtf", "public.html":
                return richTextContent(type: type, data: data)
            case "public.png", "public.tiff", "public.jpeg", "public.heic", "com.compuserve.gif":
                return imageContent(type: type, data: data)
            case "public.file-url":
                return fileContent(type: type, data: data)
            default:
                return nil
            }
        }
    }

    private func isFilteredType(_ type: String) -> Bool {
        type.hasPrefix("dyn.") || type.hasPrefix("com.microsoft.ole.source.")
    }

    private func textContent(type: String, data: Data) -> ClipboardContent? {
        guard settings.recordText,
              let text = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return nil
        }

        return ClipboardContent(
            type: type,
            storage: .inlineText(trimmedText),
            previewText: trimmedText
        )
    }

    private func richTextContent(type: String, data: Data) -> ClipboardContent? {
        guard settings.recordText else {
            return nil
        }

        return ClipboardContent(
            type: type,
            storage: .inlineData(data),
            previewText: richPreviewText(type: type, data: data)
        )
    }

    private func imageContent(type: String, data: Data) -> ClipboardContent? {
        guard settings.recordImages else {
            return nil
        }

        guard let fileName = try? assetStore.write(data, preferredExtension: preferredExtension(for: type)) else {
            return nil
        }

        return ClipboardContent(
            type: type,
            storage: .asset(fileName: fileName),
            previewText: "Image"
        )
    }

    private func fileContent(type: String, data: Data) -> ClipboardContent? {
        guard settings.recordFiles else {
            return nil
        }

        let fileName = fileName(from: data)

        return ClipboardContent(
            type: type,
            storage: .inlineData(data),
            previewText: fileName,
            fileNames: fileName.map { [$0] } ?? []
        )
    }

    private func richPreviewText(type: String, data: Data) -> String? {
        let documentType: NSAttributedString.DocumentType
        switch type {
        case "public.rtf":
            documentType = .rtf
        case "public.html":
            documentType = .html
        default:
            return nil
        }

        guard let attributedString = try? NSAttributedString(
            data: data,
            options: [.documentType: documentType],
            documentAttributes: nil
        ) else {
            return nil
        }

        let trimmedText = attributedString.string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedText.isEmpty ? nil : trimmedText
    }

    private func fileName(from data: Data) -> String? {
        guard let string = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !string.isEmpty
        else {
            return nil
        }

        if let url = URL(string: string), !url.lastPathComponent.isEmpty {
            return url.lastPathComponent
        }

        let url = URL(fileURLWithPath: string)
        return url.lastPathComponent.isEmpty ? nil : url.lastPathComponent
    }

    private func preferredExtension(for type: String) -> String {
        switch type {
        case "public.png":
            return "png"
        case "public.tiff":
            return "tiff"
        case "public.jpeg":
            return "jpg"
        case "public.heic":
            return "heic"
        case "com.compuserve.gif":
            return "gif"
        default:
            return "bin"
        }
    }

    private func title(for contents: [ClipboardContent]) -> String {
        if let previewText = contents
            .lazy
            .compactMap(\.previewText)
            .first(where: { !$0.isEmpty }) {
            return previewText
        }

        let kinds = contents.map(\.kind)

        if kinds.contains(.image) {
            return "Image"
        }

        if kinds.contains(.file) {
            return "File"
        }

        if kinds.contains(.richText) {
            return "Rich Text"
        }

        if kinds.contains(.text) {
            return "Text"
        }

        return "Clipboard Item"
    }
}
