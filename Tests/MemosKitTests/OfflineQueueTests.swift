import XCTest
@testable import MemosKit

final class OfflineQueueTests: XCTestCase {

    private func makeTempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("memos_queue_test_\(UUID().uuidString).json")
    }

    func testEnqueueAndPendingItems() {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let queue = OfflineQueue(storageURL: url)

        queue.enqueue(.create(content: "hello #灵感", visibility: .private, attachments: nil, archiveAfterCreate: false))
        XCTAssertEqual(queue.pendingCount, 1)
        XCTAssertEqual(queue.pendingItems[0].retryCount, 0)

        if case .create(let content, let vis, let attachments, let archive) = queue.pendingItems[0].action {
            XCTAssertEqual(content, "hello #灵感")
            XCTAssertEqual(vis, .private)
            XCTAssertNil(attachments)
            XCTAssertFalse(archive)
        } else { XCTFail("Expected create action") }
    }

    /// 等待后台写盘落地。
    ///
    /// `persist()` 把写入交给后台任务且不阻塞调用方，所以不能按固定时长等待：
    /// 后台任务的调度时机取决于机器负载，固定等待会在空闲机器上通过、在繁忙机器上
    /// 失败。await 写入任务本身即可确定性地等到落盘完成，与负载无关。
    /// 该任务内部已捕获全部错误，必定结束，因此无需再加超时兜底。
    private func waitForPersistedFile(of queue: OfflineQueue) async {
        guard let task = queue.lastPersist else {
            return XCTFail("入队后没有可等待的写入任务")
        }
        await task.value
    }

    func testPersistenceAcrossInstances() async throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let queue1 = OfflineQueue(storageURL: url)
        queue1.enqueue(.create(content: "persist me", visibility: .private, attachments: nil, archiveAfterCreate: false))

        await waitForPersistedFile(of: queue1)

        let queue2 = OfflineQueue(storageURL: url)
        // 用 XCTUnwrap 取值：直接下标访问空数组会触发致命错误，
        // 把断言失败变成崩溃并掩盖真正的失败原因
        let item = try XCTUnwrap(queue2.pendingItems.first, "第二个实例应从磁盘恢复出待处理项")
        XCTAssertEqual(queue2.pendingCount, 1)
        guard case .create(let content, _, _, _) = item.action else {
            return XCTFail("Expected create action")
        }
        XCTAssertEqual(content, "persist me")
    }

    func testRemoveItem() {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let queue = OfflineQueue(storageURL: url)

        queue.enqueue(.create(content: "to delete", visibility: .private, attachments: nil, archiveAfterCreate: false))
        let itemId = queue.pendingItems[0].id
        queue.removeItem(itemId)
        XCTAssertEqual(queue.pendingCount, 0)
    }

    func testUpdateItem() {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let queue = OfflineQueue(storageURL: url)

        queue.enqueue(.create(content: "original", visibility: .private, attachments: nil, archiveAfterCreate: false))
        let itemId = queue.pendingItems[0].id

        queue.updateItem(itemId, action: .create(content: "edited", visibility: .private, attachments: nil, archiveAfterCreate: false))

        if case .create(let content, _, _, _) = queue.pendingItems[0].action {
            XCTAssertEqual(content, "edited")
        } else { XCTFail("Expected create action") }
    }

    func testArchiveAfterCreateFlag() {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let queue = OfflineQueue(storageURL: url)

        queue.enqueue(.create(content: "done task", visibility: .private, attachments: nil, archiveAfterCreate: false))
        let itemId = queue.pendingItems[0].id

        queue.updateItem(itemId, action: .create(content: "done task", visibility: .private, attachments: nil, archiveAfterCreate: true))

        if case .create(_, _, _, let archive) = queue.pendingItems[0].action {
            XCTAssertTrue(archive)
        } else { XCTFail("Expected create action") }
    }
}
