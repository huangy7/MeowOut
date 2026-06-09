import XCTest
@testable import MemosKit

final class MemoCacheTests: XCTestCase {

    private func makeTempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("memos_cache_test_\(UUID().uuidString).json")
    }

    private func sampleMemo(id: String) -> Memo {
        Memo(name: "memos/\(id)", creator: "users/1",
             createTime: Date(), updateTime: Date(),
             content: "test \(id)", visibility: .private, state: .normal,
             tags: [], pinned: false, snippet: "test", property: nil)
    }

    func testSaveAndLoad() async throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let cache1 = MemoCache(storageURL: url)
        cache1.save(memos: [sampleMemo(id: "1"), sampleMemo(id: "2")])

        try await Task.sleep(nanoseconds: 100_000_000)

        let cache2 = MemoCache(storageURL: url)
        XCTAssertEqual(cache2.memos.count, 2)
        XCTAssertEqual(cache2.memos[0].id, "1")
    }

    func testMaxCacheSize() {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let cache = MemoCache(storageURL: url, maxItems: 3)
        let memos = (1...5).map { sampleMemo(id: "\($0)") }
        cache.save(memos: memos)

        XCTAssertEqual(cache.memos.count, 3)
    }

    func testLastRefreshTime() {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let cache = MemoCache(storageURL: url)
        XCTAssertNil(cache.lastRefreshTime)

        cache.save(memos: [sampleMemo(id: "1")])
        XCTAssertNotNil(cache.lastRefreshTime)
    }

    func testNeedsRefresh() {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let cache = MemoCache(storageURL: url)
        XCTAssertTrue(cache.needsRefresh(threshold: 30))

        cache.save(memos: [])
        XCTAssertFalse(cache.needsRefresh(threshold: 30))
    }

    func testEmptyCacheOnFreshStart() {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let cache = MemoCache(storageURL: url)
        XCTAssertTrue(cache.memos.isEmpty)
    }
}
