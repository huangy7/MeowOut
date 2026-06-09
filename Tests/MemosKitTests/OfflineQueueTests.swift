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

    func testPersistenceAcrossInstances() async throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let queue1 = OfflineQueue(storageURL: url)
        queue1.enqueue(.create(content: "persist me", visibility: .private, attachments: nil, archiveAfterCreate: false))

        try await Task.sleep(nanoseconds: 100_000_000)

        let queue2 = OfflineQueue(storageURL: url)
        XCTAssertEqual(queue2.pendingCount, 1)
        if case .create(let content, _, _, _) = queue2.pendingItems[0].action {
            XCTAssertEqual(content, "persist me")
        } else { XCTFail("Expected create action") }
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
