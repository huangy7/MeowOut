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

        queue.enqueue(.create(content: "hello #灵感", visibility: .private, archiveAfterCreate: false))
        XCTAssertEqual(queue.pendingCount, 1)
        XCTAssertEqual(queue.pendingItems[0].retryCount, 0)

        if case .create(let content, let vis, let archive) = queue.pendingItems[0].action {
            XCTAssertEqual(content, "hello #灵感")
            XCTAssertEqual(vis, .private)
            XCTAssertFalse(archive)
        } else { XCTFail("Expected create action") }
    }

    func testPersistenceAcrossInstances() {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let queue1 = OfflineQueue(storageURL: url)
        queue1.enqueue(.create(content: "persist me", visibility: .private, archiveAfterCreate: false))

        let queue2 = OfflineQueue(storageURL: url)
        XCTAssertEqual(queue2.pendingCount, 1)
        if case .create(let content, _, _) = queue2.pendingItems[0].action {
            XCTAssertEqual(content, "persist me")
        } else { XCTFail("Expected create action") }
    }

    func testRemoveItem() {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let queue = OfflineQueue(storageURL: url)

        queue.enqueue(.create(content: "to delete", visibility: .private, archiveAfterCreate: false))
        let itemId = queue.pendingItems[0].id
        queue.removeItem(itemId)
        XCTAssertEqual(queue.pendingCount, 0)
    }

    func testUpdateItem() {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let queue = OfflineQueue(storageURL: url)

        queue.enqueue(.create(content: "original", visibility: .private, archiveAfterCreate: false))
        let itemId = queue.pendingItems[0].id

        queue.updateItem(itemId, action: .create(content: "edited", visibility: .private, archiveAfterCreate: false))

        if case .create(let content, _, _) = queue.pendingItems[0].action {
            XCTAssertEqual(content, "edited")
        } else { XCTFail("Expected create action") }
    }

    func testArchiveAfterCreateFlag() {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let queue = OfflineQueue(storageURL: url)

        queue.enqueue(.create(content: "done task", visibility: .private, archiveAfterCreate: false))
        let itemId = queue.pendingItems[0].id

        queue.updateItem(itemId, action: .create(content: "done task", visibility: .private, archiveAfterCreate: true))

        if case .create(_, _, let archive) = queue.pendingItems[0].action {
            XCTAssertTrue(archive)
        } else { XCTFail("Expected create action") }
    }
}
