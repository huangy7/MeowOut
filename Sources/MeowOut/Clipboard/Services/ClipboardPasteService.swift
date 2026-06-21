import AppKit
import ApplicationServices
import Carbon
import Foundation

public protocol ClipboardPasteboardWriting: AnyObject {
    func clearContents()
    @discardableResult
    func setData(_ data: Data, forType type: String) -> Bool
}

public final class NSPasteboardClipboardWriter: ClipboardPasteboardWriting {
    private let pasteboard: NSPasteboard

    public init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    public func clearContents() {
        pasteboard.clearContents()
    }

    @discardableResult
    public func setData(_ data: Data, forType type: String) -> Bool {
        pasteboard.setData(data, forType: NSPasteboard.PasteboardType(type))
    }
}

public protocol ClipboardPasteEventPosting: AnyObject {
    func postPasteShortcut()
}

public final class CGEventPasteEventPoster: ClipboardPasteEventPosting {
    public init() {}

    public func postPasteShortcut() {
        let vKeyCode: CGKeyCode = 9
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            return
        }
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        else {
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}

public final class ClipboardPasteService {
    public static let shared = ClipboardPasteService()

    private let writer: ClipboardPasteboardWriting
    private let eventPoster: ClipboardPasteEventPosting
    private let assetStore: ClipboardAssetStore
    private let notificationCenter: NotificationCenter
    private let canPasteAutomatically: () -> Bool

    public init(
        writer: ClipboardPasteboardWriting = NSPasteboardClipboardWriter(),
        eventPoster: ClipboardPasteEventPosting = CGEventPasteEventPoster(),
        assetStore: ClipboardAssetStore = .applicationSupportStore,
        notificationCenter: NotificationCenter = .default,
        canPasteAutomatically: @escaping () -> Bool = {
            AXIsProcessTrusted() && !IsSecureEventInputEnabled()
        }
    ) {
        self.writer = writer
        self.eventPoster = eventPoster
        self.assetStore = assetStore
        self.notificationCenter = notificationCenter
        self.canPasteAutomatically = canPasteAutomatically
    }

    public func copy(_ item: ClipboardItem, removeFormatting: Bool, pasteAutomatically: Bool) {
        writer.clearContents()

        var didWritePayload = false
        for content in writableContents(for: item, removeFormatting: removeFormatting) {
            guard let data = data(for: content) else {
                continue
            }

            if writer.setData(data, forType: content.type) {
                didWritePayload = true
            }
        }

        let didWriteMarker = writer.setData(Data(), forType: ClipboardContent.internalMarkerType)

        guard pasteAutomatically, didWritePayload, didWriteMarker else {
            return
        }

        guard canPasteAutomatically() else {
            notificationCenter.post(name: .clipboardHistoryRequireAccessibility, object: nil)
            return
        }

        eventPoster.postPasteShortcut()
        notificationCenter.post(name: .clipboardHistoryDidPaste, object: nil)
    }

    private func writableContents(for item: ClipboardItem, removeFormatting: Bool) -> [ClipboardContent] {
        let contents = item.contents.filter { $0.type != ClipboardContent.internalMarkerType }

        guard removeFormatting else {
            return contents
        }

        let textContents = contents.filter { $0.kind == .text }
        if !textContents.isEmpty {
            return textContents
        }

        if let richTextPreview = contents
            .lazy
            .filter({ $0.kind == .richText })
            .compactMap(\.previewText)
            .first(where: { !$0.isEmpty }) {
            return [
                ClipboardContent(
                    type: "public.utf8-plain-text",
                    storage: .inlineText(richTextPreview),
                    previewText: richTextPreview
                ),
            ]
        }

        return contents
    }

    private func data(for content: ClipboardContent) -> Data? {
        switch content.storage {
        case let .inlineText(text):
            return Data(text.utf8)
        case let .inlineData(data):
            return data
        case let .asset(fileName):
            return try? assetStore.read(fileName: fileName)
        }
    }
}
