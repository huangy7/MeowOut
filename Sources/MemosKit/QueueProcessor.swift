import Foundation
import Network

public class QueueProcessor: @unchecked Sendable {
    public static let shared = QueueProcessor()

    private let queue: OfflineQueue
    private let client: MemosClient
    private var pathMonitor: NWPathMonitor?
    private var retryTask: Task<Void, Never>?
    private var processingTask: Task<Void, Never>?
    private let lock = NSLock()

    public init(queue: OfflineQueue = .shared, client: MemosClient = .shared) {
        self.queue = queue
        self.client = client
    }

    public func start() {
        startNetworkMonitor()
        scheduleProcessing()
    }

    public func stop() {
        pathMonitor?.cancel()
        pathMonitor = nil
        lock.lock()
        let task = retryTask
        retryTask = nil
        lock.unlock()
        task?.cancel()
    }

    public func processAll() async {
        await processNow()
    }

    public func processNow() async {
        let task = startProcessingTask(cancelScheduledRetry: true)
        await task.value
    }

    private func processPendingItems() async {
        let items = queue.pendingItems
        for item in items {
            do {
                try await processItem(item)
                queue.removeItem(item.id)
            } catch {
                queue.markRetry(item.id, error: error.localizedDescription)
            }
        }
    }

    public func enqueueAndProcess(_ action: OfflineQueue.PendingAction) {
        queue.enqueue(action)
        scheduleProcessing()
    }

    private func processItem(_ item: OfflineQueue.QueueItem) async throws {
        switch item.action {
        case .create(let content, let visibility, let attachments, let archiveAfterCreate):
            let memo = try await client.createMemo(content: content, visibility: visibility, attachments: attachments)
            if archiveAfterCreate {
                _ = try await client.updateMemo(name: memo.name, state: .archived, updateMask: ["state"])
            }
        case .update(let name, let content, let state, let attachments, let updateMask):
            _ = try await client.updateMemo(name: name, content: content, state: state, attachments: attachments, updateMask: updateMask)
        case .delete(let name):
            try await client.deleteMemo(name: name)
        }
    }

    private func scheduleProcessing() {
        _ = startProcessingTask(cancelScheduledRetry: true)
    }

    private func startProcessingTask(cancelScheduledRetry: Bool) -> Task<Void, Never> {
        lock.lock()
        if cancelScheduledRetry {
            retryTask?.cancel()
            retryTask = nil
        }
        if let processingTask {
            lock.unlock()
            return processingTask
        }
        let task = Task { [weak self] in
            guard let self else { return }
            await self.runProcessingCycle()
        }
        processingTask = task
        lock.unlock()
        return task
    }

    private func runProcessingCycle() async {
        await processPendingItems()
        finishProcessingCycle()
    }

    private func finishProcessingCycle() {
        lock.lock()
        processingTask = nil
        let shouldRetry = queue.pendingCount > 0
        lock.unlock()

        if shouldRetry {
            scheduleRetry()
        }
    }

    private func scheduleRetry() {
        let maxRetry = queue.pendingItems.map(\.retryCount).max() ?? 0
        let delay = min(Double(30 * (1 << min(maxRetry, 4))), 300)
        let task = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            let task = self.startProcessingTask(cancelScheduledRetry: false)
            await task.value
        }
        lock.lock()
        retryTask?.cancel()
        retryTask = task
        lock.unlock()
    }

    private func startNetworkMonitor() {
        pathMonitor?.cancel()
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            if path.status == .satisfied {
                self?.scheduleProcessing()
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.meowout.memos.network"))
        pathMonitor = monitor
    }
}
