// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers
import KeyboardShortcuts

/// A floating "shelf" that holds files, images, text and links you drop on it,
/// to drag back out into any app later. It's summoned at the cursor by a global
/// shortcut or, optionally, by shaking the mouse mid-drag. Items live
/// only while the app runs.
///
/// No permissions required: the shortcut is a Carbon hot key, and the shake
/// detector is a passive global mouse monitor.
final class ShelfService: ObservableObject {
    static let shared = ShelfService()
    var appState: AppState!

    struct Item: Identifiable, Equatable {
        let id: UUID
        indirect enum Payload: Equatable {
            case file(URL)
            case text(String)
            case link(URL)
            case batch([Item])
        }
        let payload: Payload
        let title: String
        let icon: NSImage
        let isImage: Bool

        init(id: UUID = UUID(), payload: Payload, title: String, icon: NSImage, isImage: Bool) {
            self.id = id
            self.payload = payload
            self.title = title
            self.icon = icon
            self.isImage = isImage
        }

        static func == (lhs: Item, rhs: Item) -> Bool { lhs.id == rhs.id }

        var isBatch: Bool {
            if case .batch = payload { return true }
            return false
        }

        var batchItems: [Item] {
            if case let .batch(items) = payload { return items }
            return []
        }

        var leafCount: Int {
            switch payload {
            case .file, .text, .link: return 1
            case let .batch(items): return items.reduce(0) { $0 + $1.leafCount }
            }
        }
    }

    @Published private(set) var items: [Item] = [] {
        didSet { scheduleRefit() }
    }
    /// Ids of tiles the user has selected; a drag of any selected tile drags
    /// the whole selection out together.
    @Published private(set) var selection: Set<UUID> = []
    @Published private(set) var expandedBatches: Set<UUID> = []

    private var panel: NSPanel?
    private var mouseMonitor: Any?
    private var shakeSamples: [(t: TimeInterval, x: CGFloat)] = []
    private var lastSummon: TimeInterval = 0
    private let autoHideDelay: TimeInterval = 5
    private let autoHideFadeDuration: TimeInterval = 0.22
    private var autoHideTimer: Timer?
    private var autoHideFadeTimer: Timer?
    private var autoHideFadeStart: Date?
    private var pointerInsidePanel = false
    @Published private(set) var dropTargeted = false
    private var interactionDepth = 0
    /// Drag-pasteboard state captured at mouse-down. Finder bumps the change
    /// count after this point; Dock stacks can publish the drag contents first.
    private var dragPasteboardBaseline = DragPasteboardSnapshot.empty
    private var dragBeganInDock = false
    private var activeInternalDragIDs: [UUID] = []
    private var internalDragWasMerged = false

    private struct DragPasteboardSnapshot {
        let changeCount: Int
        let hasDroppableContent: Bool

        static let empty = DragPasteboardSnapshot(changeCount: 0, hasDroppableContent: false)
    }

    private let tempDir: URL = {
        let id = Bundle.main.bundleIdentifier ?? "com.vorssaint.utils"
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VorssaintShelf", isDirectory: true)
            .appendingPathComponent(id, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private init() {
        cleanTemporaryFiles()
        cleanLegacyTemporaryFiles()
    }

    var isVisible: Bool { panel?.isVisible == true }
    var itemCount: Int { items.reduce(0) { $0 + $1.leafCount } }
    var visibleItems: [Item] { visibleItems(in: items) }

    static let tileDropTypes: [NSPasteboard.PasteboardType] = [
        .fileURL,
        .URL,
        .string,
        .tiff,
        .png,
        NSPasteboard.PasteboardType(UTType.gif.identifier),
        NSPasteboard.PasteboardType("NSFilenamesPboardType"),
        NSPasteboard.PasteboardType("NSURLPboardType"),
        NSPasteboard.PasteboardType(UTType.fileURL.identifier),
        NSPasteboard.PasteboardType(UTType.image.identifier),
        NSPasteboard.PasteboardType(UTType.url.identifier),
        NSPasteboard.PasteboardType(UTType.text.identifier),
        NSPasteboard.PasteboardType(UTType.plainText.identifier),
    ]

    // MARK: - Lifecycle

    func start(appState: AppState) {
        self.appState = appState
        syncWithPreferences()
        KeyboardShortcuts.onKeyDown(for: .toggleShelf) { [weak self] in
            guard UserDefaults.standard.bool(forKey: "shelfEnabled") else { return }
            self?.toggle()
        }
    }

    func syncWithPreferences() {
        if UserDefaults.standard.object(forKey: "shelfEnabled") == nil {
            UserDefaults.standard.set(true, forKey: "shelfEnabled")
        }
        if UserDefaults.standard.object(forKey: "shelfShakeToOpen") == nil {
            UserDefaults.standard.set(true, forKey: "shelfShakeToOpen")
        }
        
        if UserDefaults.standard.bool(forKey: "shelfEnabled") {
            syncShakeMonitor()
        } else {
            stopShakeMonitor()
            hide()
        }
    }

    func syncShakeMonitor() {
        let wanted = UserDefaults.standard.bool(forKey: "shelfEnabled")
            && UserDefaults.standard.bool(forKey: "shelfShakeToOpen")
        if wanted { startShakeMonitor() } else { stopShakeMonitor() }
    }

    // MARK: - Triggers

    private func startShakeMonitor() {
        guard mouseMonitor == nil else { return }
        dragPasteboardBaseline = dragPasteboardSnapshot()
        dragBeganInDock = false
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged]) { [weak self] event in
            guard let self else { return }
            if event.type == .leftMouseDown {
                // Capture the drag pasteboard before any drag starts. Finder
                // changes it after this; Dock stacks may already have filled it.
                self.dragPasteboardBaseline = self.dragPasteboardSnapshot()
                self.dragBeganInDock = self.eventBelongsToDock(event)
                self.shakeSamples.removeAll()
            } else {
                self.dragBeganInDock = self.dragBeganInDock || self.eventBelongsToDock(event)
                self.handleDrag(event)
            }
        }
    }

    private func stopShakeMonitor() {
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
        shakeSamples.removeAll()
    }

    /// Detects a back-and-forth shake of the pointer during a drag: enough
    /// horizontal direction reversals and travel in a short window.
    private func handleDrag(_ event: NSEvent) {
        let t = event.timestamp
        shakeSamples.append((t, NSEvent.mouseLocation.x))
        shakeSamples.removeAll { t - $0.t > 0.5 }
        guard shakeSamples.count >= 5 else { return }

        var reversals = 0
        var travel: CGFloat = 0
        var lastDirection = 0
        for i in 1..<shakeSamples.count {
            let dx = shakeSamples[i].x - shakeSamples[i - 1].x
            travel += abs(dx)
            let direction = dx > 6 ? 1 : (dx < -6 ? -1 : 0)
            if direction != 0 {
                if lastDirection != 0, direction != lastDirection { reversals += 1 }
                lastDirection = direction
            }
        }
        if reversals >= 3, travel > 220, t - lastSummon > 1.0 {
            // Only when content is actually being dragged — not when a window is
            // being moved (nothing droppable, so the shelf shouldn't appear).
            guard isContentDragActive() else { return }
            lastSummon = t
            shakeSamples.removeAll()
            DispatchQueue.main.async { [weak self] in self?.summon() }
        }
    }

    private func isContentDragActive() -> Bool {
        let snapshot = dragPasteboardSnapshot()
        if snapshot.changeCount != dragPasteboardBaseline.changeCount { return true }
        return dragBeganInDock && snapshot.hasDroppableContent
    }

    private func dragPasteboardSnapshot() -> DragPasteboardSnapshot {
        let pasteboard = NSPasteboard(name: .drag)
        return DragPasteboardSnapshot(
            changeCount: pasteboard.changeCount,
            hasDroppableContent: pasteboardHasDroppableContent(pasteboard)
        )
    }

    private func pasteboardHasDroppableContent(_ pasteboard: NSPasteboard) -> Bool {
        guard let items = pasteboard.pasteboardItems, !items.isEmpty else { return false }
        let directTypes: Set<String> = [
            NSPasteboard.PasteboardType.fileURL.rawValue,
            NSPasteboard.PasteboardType.string.rawValue,
            NSPasteboard.PasteboardType.tiff.rawValue,
            NSPasteboard.PasteboardType.png.rawValue,
            UTType.gif.identifier,
            UTType.fileURL.identifier,
            UTType.image.identifier,
            UTType.url.identifier,
            UTType.text.identifier,
            UTType.plainText.identifier,
            "NSFilenamesPboardType",
            "NSURLPboardType"
        ]
        let supportedUTTypes: [UTType] = [.fileURL, .gif, .image, .url, .text, .plainText]

        for item in items {
            for type in item.types {
                if directTypes.contains(type.rawValue) { return true }
                guard let utType = UTType(type.rawValue) else { continue }
                if supportedUTTypes.contains(where: { utType.conforms(to: $0) }) { return true }
            }
        }
        return false
    }

    private func eventBelongsToDock(_ event: NSEvent) -> Bool {
        if let cgEvent = event.cgEvent {
            let pid = pid_t(cgEvent.getIntegerValueField(.eventSourceUnixProcessID))
            if isDockProcess(pid) { return true }
        }

        guard event.windowNumber > 0 else { return false }
        guard let infos = CGWindowListCopyWindowInfo(.optionIncludingWindow,
                                                     CGWindowID(event.windowNumber)) as? [[String: Any]],
              let info = infos.first else { return false }
        if let pidNumber = info[kCGWindowOwnerPID as String] as? NSNumber,
           isDockProcess(pid_t(pidNumber.int32Value)) {
            return true
        }
        return (info[kCGWindowOwnerName as String] as? String) == "Dock"
    }

    private func isDockProcess(_ pid: pid_t) -> Bool {
        guard pid > 0 else { return false }
        return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "com.apple.dock"
    }

    // MARK: - Items

    /// Order matters for fidelity: a file is always a file, but a web image
    /// drag carries both an image and its page URL — prefer the image, and
    /// only fall back to treating a URL as a link when nothing richer exists.
    func accept(providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.enumerated().filter {
            $0.element.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }
        if fileProviders.count > 1, fileProviders.count == providers.count {
            acceptFileBatch(providers: fileProviders)
            return true
        }

        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                handled = true
                _ = provider.loadObject(ofClass: URL.self) { [weak self] url, _ in
                    guard let url, url.isFileURL else { return }
                    DispatchQueue.main.async { self?.addFile(url) }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.gif.identifier) {
                handled = true
                _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.gif.identifier) { [weak self] data, _ in
                    guard let data, !data.isEmpty else { return }
                    DispatchQueue.main.async { self?.addGIF(data: data) }
                }
            } else if provider.canLoadObject(ofClass: NSImage.self) {
                handled = true
                _ = provider.loadObject(ofClass: NSImage.self) { [weak self] image, _ in
                    guard let image = image as? NSImage else { return }
                    DispatchQueue.main.async { self?.addImage(image) }
                }
            } else if provider.canLoadObject(ofClass: URL.self) {
                handled = true
                _ = provider.loadObject(ofClass: URL.self) { [weak self] url, _ in
                    guard let url else { return }
                    DispatchQueue.main.async {
                        url.isFileURL ? self?.addFile(url) : self?.addLink(url)
                    }
                }
            } else if provider.canLoadObject(ofClass: NSString.self) {
                handled = true
                _ = provider.loadObject(ofClass: NSString.self) { [weak self] string, _ in
                    guard let string = string as? String else { return }
                    DispatchQueue.main.async { self?.addText(string) }
                }
            }
        }
        return handled
    }

    private func acceptFileBatch(providers: [(offset: Int, element: NSItemProvider)]) {
        let group = DispatchGroup()
        let lock = NSLock()
        var loaded: [(Int, URL)] = []

        for (index, provider) in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url, url.isFileURL {
                    lock.lock()
                    loaded.append((index, url))
                    lock.unlock()
                }
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            let urls = loaded.sorted { $0.0 < $1.0 }.map(\.1)
            guard urls.count > 1 else {
                if let url = urls.first { self?.addFile(url) }
                return
            }
            self?.addFileBatch(urls)
        }
    }

    func removeItem(_ id: UUID) {
        var removed: [Item] = []
        removeItems(Set([id]), from: &items, removed: &removed)
        cleanSelectionState()
        retireTemporaryPayloads(in: removed)
        noteInteraction()
    }

    /// Removes several items at once — used after a successful drag-out so the
    /// tiles you dropped elsewhere leave the shelf.
    func removeItems(_ ids: [UUID]) {
        let set = Set(ids)
        var removed: [Item] = []
        removeItems(set, from: &items, removed: &removed)
        cleanSelectionState()
        retireTemporaryPayloads(in: removed)
        noteInteraction()
    }

    func clear() {
        let removed = items
        items = []
        selection = []
        expandedBatches = []
        retireTemporaryPayloads(in: removed)
        noteInteraction()
    }

    func toggleSelection(_ id: UUID) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
        noteInteraction()
    }

    func toggleBatchExpansion(_ id: UUID) {
        guard let batch = item(withID: id), batch.isBatch else { return }
        if expandedBatches.contains(id) {
            expandedBatches.remove(id)
            selection.subtract(allIDs(in: batch.batchItems))
        } else {
            expandedBatches.insert(id)
        }
        noteInteraction()
    }

    func selectedItems() -> [Item] {
        selectedItems(in: items)
    }

    func dragItems(for item: Item) -> [Item] {
        dragItems(for: [item])
    }

    func dragItems(for items: [Item]) -> [Item] {
        var result: [Item] = []
        var seen = Set<UUID>()
        for item in items {
            appendDragLeaves(from: item, to: &result, seen: &seen)
        }
        return result
    }

    func beginInternalDrag(ids: [UUID]) {
        activeInternalDragIDs = ids
        internalDragWasMerged = false
    }

    func finishInternalDrag(dropAccepted: Bool) -> [UUID] {
        defer {
            activeInternalDragIDs = []
            internalDragWasMerged = false
        }
        guard dropAccepted, !internalDragWasMerged else { return [] }
        return activeInternalDragIDs
    }

    var isInternalDragActive: Bool {
        !activeInternalDragIDs.isEmpty
    }

    func canMergePasteboard(_ pasteboard: NSPasteboard, into targetID: UUID) -> Bool {
        if !activeInternalDragIDs.isEmpty {
            return canMergeInternalDrag(into: targetID)
        }
        return pasteboardCanCreateItem(pasteboard)
    }

    func mergePasteboard(_ pasteboard: NSPasteboard, into targetID: UUID) -> Bool {
        if !activeInternalDragIDs.isEmpty {
            return mergeInternalDrag(into: targetID)
        }
        let additions = items(from: pasteboard)
        guard !additions.isEmpty else { return false }
        return merge(additions, into: targetID)
    }

    func canAcceptPasteboard(_ pasteboard: NSPasteboard) -> Bool {
        pasteboardCanCreateItem(pasteboard)
    }

    func accept(pasteboard: NSPasteboard) -> Bool {
        let fileURLs = fileURLs(from: pasteboard)
        if fileURLs.count > 1 {
            addFileBatch(fileURLs)
            return true
        }
        let additions = items(from: pasteboard)
        guard !additions.isEmpty else { return false }
        items.append(contentsOf: additions)
        noteInteraction()
        return true
    }

    /// The pasteboard representation used when dragging an item out of the shelf.
    func pasteboardWriter(for item: Item) -> NSPasteboardWriting {
        switch item.payload {
        case let .file(url): return url as NSURL
        case let .text(text): return text as NSString
        case let .link(url): return url as NSURL
        case let .batch(items):
            guard let first = dragItems(for: items).first else { return item.title as NSString }
            return pasteboardWriter(for: first)
        }
    }

    private func addFile(_ url: URL) {
        append(fileItem(for: url))
    }

    private func addFileBatch(_ urls: [URL]) {
        let children = urls.map { fileItem(for: $0) }
        append(batchItem(children: children))
    }

    private func addImage(_ image: NSImage) {
        guard let item = imageItem(for: image) else { return }
        append(item)
    }

    private func addGIF(data: Data) {
        guard let item = gifItem(for: data) else { return }
        append(item)
    }

    private func addText(_ string: String) {
        guard let item = textItem(for: string) else { return }
        append(item)
    }

    private func addLink(_ url: URL) {
        append(linkItem(for: url))
    }

    private func fileItem(for url: URL) -> Item {
        let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "heif", "tiff", "bmp", "webp"]
        let isImage = imageExtensions.contains(url.pathExtension.lowercased())
        let fallbackIcon = NSWorkspace.shared.icon(forFile: url.path)
        let icon = (isImage ? ImageThumbnailer.thumbnail(for: url) : nil)
            ?? ImageThumbnailer.thumbnail(for: fallbackIcon)
            ?? fallbackIcon
        return Item(payload: .file(url), title: url.lastPathComponent, icon: icon, isImage: isImage)
    }

    private func imageItem(for image: NSImage) -> Item? {
        let url = tempDir.appendingPathComponent("\(UUID().uuidString).png")
        let icon = ImageThumbnailer.thumbnail(for: image) ?? symbol("photo")
        if let png = autoreleasepool(invoking: { () -> Data? in
            guard let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff) else { return nil }
            return rep.representation(using: .png, properties: [:])
        }) {
            try? png.write(to: url)
            return Item(payload: .file(url), title: I18n.localized("shelf_item_image", language: AppState().language), icon: icon, isImage: true)
        }
        return nil
    }

    private func gifItem(for data: Data) -> Item? {
        let url = tempDir.appendingPathComponent("\(UUID().uuidString).gif")
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            return nil
        }
        let icon = ImageThumbnailer.thumbnail(for: url) ?? symbol("photo")
        return Item(payload: .file(url), title: "GIF", icon: icon, isImage: true)
    }

    private func textItem(for string: String) -> Item? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let firstLine = trimmed.split(whereSeparator: \.isNewline).first.map(String.init) ?? trimmed
        let icon = symbol("doc.plaintext")
        return Item(payload: .text(string), title: String(firstLine.prefix(48)), icon: icon, isImage: false)
    }

    private func linkItem(for url: URL) -> Item {
        Item(payload: .link(url), title: url.host ?? url.absoluteString, icon: symbol("link"), isImage: false)
    }

    private func append(_ item: Item) {
        items.append(item)
        noteInteraction()
    }

    private func batchItem(id: UUID = UUID(), children: [Item]) -> Item {
        let total = children.reduce(0) { $0 + $1.leafCount }
        let title = children.first.map { "\($0.title) +\(max(0, total - 1))" } ?? ""
        let icon = children.first?.icon ?? symbol("doc.on.doc")
        return Item(id: id, payload: .batch(children), title: title, icon: icon, isImage: false)
    }

    private func items(from pasteboard: NSPasteboard) -> [Item] {
        let fileURLs = fileURLs(from: pasteboard)
        if !fileURLs.isEmpty {
            return fileURLs.map { fileItem(for: $0) }
        }
        if let gif = gifData(from: pasteboard),
           let item = gifItem(for: gif) {
            return [item]
        }
        if let image = NSImage(pasteboard: pasteboard),
           let item = imageItem(for: image) {
            return [item]
        }
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [NSURL],
           let url = urls.map({ $0 as URL }).first(where: { !$0.isFileURL }) {
            return [linkItem(for: url)]
        }
        if let string = pasteboard.string(forType: .string),
           let item = textItem(for: string) {
            return [item]
        }
        return []
    }

    private func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        let fileOptions: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: fileOptions) as? [NSURL],
           !urls.isEmpty {
            return unique(urls.map { $0 as URL }.filter(\.isFileURL))
        }
        if let paths = pasteboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String],
           !paths.isEmpty {
            return unique(paths.map { URL(fileURLWithPath: $0) })
        }
        return []
    }

    private func pasteboardCanCreateItem(_ pasteboard: NSPasteboard) -> Bool {
        if !fileURLs(from: pasteboard).isEmpty {
            return true
        }
        if pasteboardHasGIF(pasteboard) {
            return true
        }
        if pasteboardHasImage(pasteboard) {
            return true
        }
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [NSURL],
           urls.contains(where: { !($0 as URL).isFileURL }) {
            return true
        }
        if let string = pasteboard.string(forType: .string),
           !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        return false
    }

    private func gifData(from pasteboard: NSPasteboard) -> Data? {
        for type in pasteboard.types ?? [] {
            guard pasteboardTypeIsGIF(type),
                  let data = pasteboard.data(forType: type),
                  !data.isEmpty else {
                continue
            }
            return data
        }
        return nil
    }

    private func pasteboardHasGIF(_ pasteboard: NSPasteboard) -> Bool {
        (pasteboard.types ?? []).contains(where: pasteboardTypeIsGIF)
    }

    private func pasteboardHasImage(_ pasteboard: NSPasteboard) -> Bool {
        for type in pasteboard.types ?? [] {
            if pasteboardTypeIsGIF(type) { continue }
            if type == .png || type == .tiff { return true }
            if UTType(type.rawValue)?.conforms(to: .image) == true { return true }
        }
        return false
    }

    private func pasteboardTypeIsGIF(_ type: NSPasteboard.PasteboardType) -> Bool {
        type.rawValue == UTType.gif.identifier
            || UTType(type.rawValue)?.conforms(to: .gif) == true
    }

    private func unique(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    private func canMergeInternalDrag(into targetID: UUID) -> Bool {
        guard !activeInternalDragIDs.isEmpty,
              !activeInternalDragIDs.contains(targetID),
              let target = item(withID: targetID)
        else { return false }
        let active = Set(activeInternalDragIDs)
        guard allIDs(in: target.batchItems).isDisjoint(with: active) else { return false }
        return !items(withIDs: active, in: items).isEmpty
    }

    private func mergeInternalDrag(into targetID: UUID) -> Bool {
        guard canMergeInternalDrag(into: targetID) else { return false }
        let sourceIDs = Set(activeInternalDragIDs)
        let additions = dragItems(for: items(withIDs: sourceIDs, in: items))
        guard !additions.isEmpty else { return false }

        var moved: [Item] = []
        removeItems(sourceIDs, from: &items, removed: &moved)
        guard merge(additions, into: targetID) else { return false }
        internalDragWasMerged = true
        return true
    }

    private func merge(_ additions: [Item], into targetID: UUID) -> Bool {
        let leaves = dragItems(for: additions)
        guard !leaves.isEmpty,
              leaves.allSatisfy({ $0.id != targetID }),
              merge(leaves, into: targetID, in: &items)
        else { return false }
        cleanSelectionState()
        noteInteraction()
        return true
    }

    private func merge(_ additions: [Item], into targetID: UUID, in items: inout [Item]) -> Bool {
        for index in items.indices {
            if items[index].id == targetID {
                switch items[index].payload {
                case let .batch(children):
                    items[index] = batchItem(id: items[index].id, children: children + additions)
                case .file, .text, .link:
                    items[index] = batchItem(id: items[index].id, children: [items[index]] + additions)
                }
                return true
            }

            guard case var .batch(children) = items[index].payload else { continue }
            if merge(additions, into: targetID, in: &children) {
                items[index] = batchItem(id: items[index].id, children: children)
                return true
            }
        }
        return false
    }

    private func retireTemporaryPayloads(in removed: [Item]) {
        let urls = removed.flatMap { temporaryPayloadURLs(in: $0) }
        guard !urls.isEmpty else { return }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + .seconds(10 * 60)) {
            let fm = FileManager.default
            for url in urls where self.isShelfTemporaryFile(url) {
                try? fm.removeItem(at: url)
            }
        }
    }

    private func temporaryPayloadURLs(in item: Item) -> [URL] {
        switch item.payload {
        case let .file(url):
            return isShelfTemporaryFile(url) ? [url] : []
        case .text, .link:
            return []
        case let .batch(items):
            return items.flatMap { temporaryPayloadURLs(in: $0) }
        }
    }

    private func removeItems(_ ids: Set<UUID>, from items: inout [Item], removed: inout [Item]) {
        var kept: [Item] = []
        for item in items {
            if ids.contains(item.id) {
                removed.append(item)
                continue
            }

            guard case var .batch(children) = item.payload else {
                kept.append(item)
                continue
            }

            removeItems(ids, from: &children, removed: &removed)
            if children.isEmpty {
                expandedBatches.remove(item.id)
            } else if children.count == 1 {
                expandedBatches.remove(item.id)
                kept.append(children[0])
            } else {
                kept.append(batchItem(id: item.id, children: children))
            }
        }
        items = kept
    }

    private func visibleItems(in items: [Item]) -> [Item] {
        var result: [Item] = []
        for item in items {
            result.append(item)
            if expandedBatches.contains(item.id), case let .batch(children) = item.payload {
                result.append(contentsOf: visibleItems(in: children))
            }
        }
        return result
    }

    private func selectedItems(in items: [Item]) -> [Item] {
        var result: [Item] = []
        for item in items {
            if selection.contains(item.id) { result.append(item) }
            if case let .batch(children) = item.payload {
                result.append(contentsOf: selectedItems(in: children))
            }
        }
        return result
    }

    private func appendDragLeaves(from item: Item, to result: inout [Item], seen: inout Set<UUID>) {
        switch item.payload {
        case .file, .text, .link:
            guard seen.insert(item.id).inserted else { return }
            result.append(item)
        case let .batch(items):
            for child in items {
                appendDragLeaves(from: child, to: &result, seen: &seen)
            }
        }
    }

    private func item(withID id: UUID) -> Item? {
        item(withID: id, in: items)
    }

    private func item(withID id: UUID, in items: [Item]) -> Item? {
        for item in items {
            if item.id == id { return item }
            if case let .batch(children) = item.payload,
               let found = self.item(withID: id, in: children) {
                return found
            }
        }
        return nil
    }

    private func items(withIDs ids: Set<UUID>, in items: [Item]) -> [Item] {
        var result: [Item] = []
        for item in items {
            if ids.contains(item.id) { result.append(item) }
            if case let .batch(children) = item.payload {
                result.append(contentsOf: self.items(withIDs: ids, in: children))
            }
        }
        return result
    }

    private func allIDs(in items: [Item]) -> Set<UUID> {
        var ids = Set<UUID>()
        for item in items {
            ids.insert(item.id)
            if case let .batch(children) = item.payload {
                ids.formUnion(allIDs(in: children))
            }
        }
        return ids
    }

    private func batchIDs(in items: [Item]) -> Set<UUID> {
        var ids = Set<UUID>()
        for item in items {
            if case let .batch(children) = item.payload {
                ids.insert(item.id)
                ids.formUnion(batchIDs(in: children))
            }
        }
        return ids
    }

    private func cleanSelectionState() {
        selection.formIntersection(allIDs(in: items))
        expandedBatches.formIntersection(batchIDs(in: items))
    }

    private func cleanTemporaryFiles() {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: tempDir,
                                                        includingPropertiesForKeys: nil) else { return }
        for url in entries where isShelfTemporaryFile(url) {
            try? fm.removeItem(at: url)
        }
    }

    private func cleanLegacyTemporaryFiles() {
        let legacyDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VorssaintShelf", isDirectory: true)
        guard legacyDir != tempDir,
              let entries = try? FileManager.default.contentsOfDirectory(at: legacyDir,
                                                                         includingPropertiesForKeys: nil)
        else { return }
        for url in entries where url.pathExtension.lowercased() == "png" {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func isShelfTemporaryFile(_ url: URL) -> Bool {
        let dir = tempDir.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path.hasPrefix(dir + "/")
    }

    private func symbol(_ name: String) -> NSImage {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage()
    }

    // MARK: - Panel

    func toggle() {
        isVisible ? hide() : summon()
    }

    func summon() {
        let panel = ensurePanel()
        cancelAutoHide()
        position(panel)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        updatePointerInsidePanel()
        scheduleAutoHideIfIdle()
    }

    func hide() {
        resetAutoHide()
        panel?.orderOut(nil)
    }

    func noteInteraction() {
        guard panel?.isVisible == true else { return }
        cancelAutoHideFade()
        scheduleAutoHideIfIdle()
    }

    func setPointerInsidePanel(_ inside: Bool) {
        pointerInsidePanel = inside
        if inside {
            cancelAutoHide()
        } else {
            scheduleAutoHideIfIdle()
        }
    }

    func setDropTargeted(_ targeted: Bool) {
        guard dropTargeted != targeted else { return }
        dropTargeted = targeted
        if targeted {
            cancelAutoHide()
        } else {
            scheduleAutoHideIfIdle()
        }
    }

    func beginInteraction() {
        interactionDepth += 1
        cancelAutoHide()
    }

    func endInteraction() {
        interactionDepth = max(0, interactionDepth - 1)
        scheduleAutoHideIfIdle()
    }

    private func resetAutoHide() {
        cancelAutoHide()
        pointerInsidePanel = false
        dropTargeted = false
        interactionDepth = 0
    }

    private func cancelAutoHide() {
        autoHideTimer?.invalidate()
        autoHideTimer = nil
        cancelAutoHideFade()
    }

    private func cancelAutoHideFade() {
        autoHideFadeTimer?.invalidate()
        autoHideFadeTimer = nil
        autoHideFadeStart = nil
        panel?.alphaValue = 1
    }

    private var shouldHoldOpen: Bool {
        !items.isEmpty || pointerInsidePanel || dropTargeted || interactionDepth > 0
    }

    private func scheduleAutoHideIfIdle() {
        autoHideTimer?.invalidate()
        autoHideTimer = nil
        guard panel?.isVisible == true, !shouldHoldOpen else { return }

        autoHideTimer = Timer.scheduledTimer(withTimeInterval: autoHideDelay, repeats: false) { [weak self] _ in
            self?.autoHideIfIdle()
        }
        autoHideTimer?.tolerance = 0.5
    }

    private func autoHideIfIdle() {
        autoHideTimer?.invalidate()
        autoHideTimer = nil
        updatePointerInsidePanel()
        guard panel?.isVisible == true else { return }
        guard !shouldHoldOpen else {
            scheduleAutoHideIfIdle()
            return
        }
        fadeOutAndHide()
    }

    private func updatePointerInsidePanel() {
        guard let panel, panel.isVisible else {
            pointerInsidePanel = false
            return
        }
        pointerInsidePanel = panel.frame.contains(NSEvent.mouseLocation)
    }

    private func fadeOutAndHide() {
        guard let panel, panel.isVisible else { return }
        autoHideFadeTimer?.invalidate()
        autoHideFadeStart = Date()
        panel.alphaValue = 1

        autoHideFadeTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self, let panel = self.panel, panel.isVisible else {
                timer.invalidate()
                return
            }
            self.updatePointerInsidePanel()
            guard !self.shouldHoldOpen else {
                timer.invalidate()
                self.autoHideFadeTimer = nil
                self.autoHideFadeStart = nil
                panel.alphaValue = 1
                self.scheduleAutoHideIfIdle()
                return
            }
            let elapsed = Date().timeIntervalSince(self.autoHideFadeStart ?? Date())
            let progress = min(1, elapsed / self.autoHideFadeDuration)
            panel.alphaValue = 1 - CGFloat(progress)
            guard progress >= 1 else { return }
            timer.invalidate()
            self.autoHideFadeTimer = nil
            self.autoHideFadeStart = nil
            panel.orderOut(nil)
            panel.alphaValue = 1
            self.pointerInsidePanel = false
            self.dropTargeted = false
            self.interactionDepth = 0
        }
        autoHideFadeTimer?.tolerance = 0.02
    }

    /// Re-fits the panel to its content (anchored at the top-left) after items
    /// change while it's on screen — e.g. dropping a file onto a shelf that was
    /// summoned empty by a shake. Deferred so SwiftUI lays out first.
    private func scheduleRefit() {
        DispatchQueue.main.async { [weak self] in self?.refitIfVisible() }
    }

    private func refitIfVisible() {
        guard let panel, panel.isVisible else { return }
        let view = panel.contentViewController!.view
        view.layoutSubtreeIfNeeded()
        let size = view.fittingSize
        let top = panel.frame.maxY
        panel.setFrame(NSRect(x: panel.frame.minX, y: top - size.height, width: size.width, height: size.height),
                       display: true, animate: false)
    }

    private func position(_ panel: NSPanel) {
        let view = panel.contentViewController!.view
        view.layoutSubtreeIfNeeded()
        let size = view.fittingSize
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.withMouse.visibleFrame
        var x = mouse.x - size.width / 2
        var y = mouse.y - size.height - 16
        x = min(max(screen.minX + 8, x), screen.maxX - size.width - 8)
        y = min(max(screen.minY + 8, y), screen.maxY - size.height - 8)
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = NSPanel(contentRect: .zero,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // Not movable by background: dragging a tile must start an item drag,
        // not move the whole panel.
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let host = NSHostingController(rootView: ShelfView()
            .environmentObject(self)
            .environment(appState))
        host.sizingOptions = .preferredContentSize
        panel.contentViewController = host
        self.panel = panel
        return panel
    }
}
