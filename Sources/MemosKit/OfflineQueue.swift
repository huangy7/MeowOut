import Foundation

public class OfflineQueue: @unchecked Sendable {
    public static let shared = OfflineQueue()

    public enum PendingAction: Codable, Sendable {
        case create(content: String, visibility: MemoVisibility, archiveAfterCreate: Bool)
        case update(memoName: String, content: String?, state: MemoState?, updateMask: [String])
        case delete(memoName: String)
    }

    public struct QueueItem: Codable, Identifiable, Sendable {
        public let id: UUID
        public var action: PendingAction
        public let createdAt: Date
        public var retryCount: Int
        public var lastError: String?
    }

    private let storageURL: URL
    private var items: [QueueItem] = []
    private let lock = NSLock()

    public init(storageURL: URL? = nil) {
        if let storageURL {
            self.storageURL = storageURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("MeowOut")
            try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
            self.storageURL = appSupport.appendingPathComponent("memos_queue.json")
        }
        load()
    }

    public var pendingItems: [QueueItem] {
        lock.lock()
        defer { lock.unlock() }
        return items
    }

    public var pendingCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return items.count
    }

    public func enqueue(_ action: PendingAction) {
        lock.lock()
        let item = QueueItem(id: UUID(), action: action, createdAt: Date(), retryCount: 0, lastError: nil)
        items.append(item)
        lock.unlock()
        persist()
    }

    public func removeItem(_ id: UUID) {
        lock.lock()
        items.removeAll { $0.id == id }
        lock.unlock()
        persist()
    }

    public func updateItem(_ id: UUID, action: PendingAction) {
        lock.lock()
        if let index = items.firstIndex(where: { $0.id == id }) {
            items[index].action = action
        }
        lock.unlock()
        persist()
    }

    func markRetry(_ id: UUID, error: String) {
        lock.lock()
        if let index = items.firstIndex(where: { $0.id == id }) {
            items[index].retryCount += 1
            items[index].lastError = error
        }
        lock.unlock()
        persist()
    }

    // MARK: - Persistence

    private func load() {
        guard FileManager.default.fileExists(atPath: storageURL.path),
              let data = try? Data(contentsOf: storageURL),
              let loaded = try? JSONDecoder().decode([QueueItem].self, from: data) else { return }
        items = loaded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(pendingItems) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }
}
