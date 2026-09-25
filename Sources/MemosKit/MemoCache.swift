import Foundation

public class MemoCache: @unchecked Sendable {
    public static let shared = MemoCache()

    private struct CacheData: Codable, Sendable {
        var memos: [Memo]
        var lastRefreshTime: Date?
    }

    private let storageURL: URL
    private let maxItems: Int
    private var data: CacheData
    private let lock = NSLock()
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var lastPersistTask: Task<Void, Never>?

    public init(storageURL: URL? = nil, maxItems: Int = 200) {
        if let storageURL {
            self.storageURL = storageURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("MeowOut")
            try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
            self.storageURL = appSupport.appendingPathComponent("memos_cache.json")
        }
        self.maxItems = maxItems
        self.encoder = MemosDateCoding.makeEncoder()
        self.decoder = MemosDateCoding.makeDecoder()
        self.data = CacheData(memos: [], lastRefreshTime: nil)
        load()
    }

    public var memos: [Memo] {
        lock.lock()
        defer { lock.unlock() }
        return data.memos
    }

    public var lastRefreshTime: Date? {
        lock.lock()
        defer { lock.unlock() }
        return data.lastRefreshTime
    }

    public func needsRefresh(threshold: TimeInterval = 30) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let last = data.lastRefreshTime else { return true }
        return Date().timeIntervalSince(last) > threshold
    }

    public func save(memos: [Memo]) {
        lock.lock()
        data.memos = Array(memos.prefix(maxItems))
        data.lastRefreshTime = Date()
        lock.unlock()
        persist()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: storageURL.path),
              let raw = try? Data(contentsOf: storageURL),
              let loaded = try? decoder.decode(CacheData.self, from: raw) else { return }
        data = loaded
    }

    private func persist() {
        lock.lock()
        let snapshot = data
        lock.unlock()
        let task = JSONStorage.save(snapshot, to: storageURL) { MemosDateCoding.makeEncoder() }
        lock.lock()
        lastPersistTask = task
        lock.unlock()
    }

    /// 最近一次保存触发的写入任务。
    ///
    /// `persist()` 不阻塞调用方，写入在后台完成；需要确定性等待落盘时 await 它即可，
    /// 例如测试断言跨实例读取，或退出前确保缓存已写入。
    var lastPersist: Task<Void, Never>? {
        lock.lock()
        defer { lock.unlock() }
        return lastPersistTask
    }
}
