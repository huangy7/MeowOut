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
        JSONStorage.save(snapshot, to: storageURL) { MemosDateCoding.makeEncoder() }
    }
}
