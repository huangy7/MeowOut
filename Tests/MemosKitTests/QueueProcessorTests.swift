import XCTest
@testable import MemosKit

final class QueueProcessorTests: XCTestCase {

    private func makeTempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("memos_queue_proc_\(UUID().uuidString).json")
    }

    private func makeTestClient() throws -> MemosClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let auth = MemosAuth(
            service: "com.meowout.memos.test-\(UUID().uuidString)",
            baseURLKey: "memosBaseURL-test-\(UUID().uuidString)")
        try auth.configure(baseURL: URL(string: "https://memos.test")!, pat: "memos_pat_test")
        return MemosClient(session: URLSession(configuration: config), auth: auth)
    }

    func testProcessCreateSuccess() async throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let queue = OfflineQueue(storageURL: url)
        queue.enqueue(.create(content: "test", visibility: .private, archiveAfterCreate: false))

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let auth = MemosAuth(
            service: "com.meowout.memos.test-\(UUID().uuidString)",
            baseURLKey: "memosBaseURL-test-\(UUID().uuidString)")
        try auth.configure(baseURL: URL(string: "https://memos.test")!, pat: "memos_pat_test")
        let client = MemosClient(session: URLSession(configuration: config), auth: auth)

        MockURLProtocol.requestHandler = { request in
            let body = """
            {"name":"memos/1","creator":"users/1","createTime":"2026-05-24T10:00:00Z","updateTime":"2026-05-24T10:00:00Z","content":"test","visibility":"PRIVATE","state":"NORMAL","tags":[],"pinned":false}
            """.data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }

        let processor = QueueProcessor(queue: queue, client: client)
        await processor.processAll()
        XCTAssertEqual(queue.pendingCount, 0)
    }

    func testProcessCreateWithArchive() async throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let queue = OfflineQueue(storageURL: url)
        queue.enqueue(.create(content: "done task", visibility: .private, archiveAfterCreate: true))

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let auth = MemosAuth(
            service: "com.meowout.memos.test-\(UUID().uuidString)",
            baseURLKey: "memosBaseURL-test-\(UUID().uuidString)")
        try auth.configure(baseURL: URL(string: "https://memos.test")!, pat: "memos_pat_test")
        let client = MemosClient(session: URLSession(configuration: config), auth: auth)

        var requestCount = 0
        MockURLProtocol.requestHandler = { request in
            requestCount += 1
            if requestCount == 1 {
                XCTAssertEqual(request.httpMethod, "POST")
                let body = """
                {"name":"memos/1","creator":"users/1","createTime":"2026-05-24T10:00:00Z","updateTime":"2026-05-24T10:00:00Z","content":"done task","visibility":"PRIVATE","state":"NORMAL","tags":[],"pinned":false}
                """.data(using: .utf8)!
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
            } else {
                XCTAssertEqual(request.httpMethod, "PATCH")
                let body = """
                {"name":"memos/1","creator":"users/1","createTime":"2026-05-24T10:00:00Z","updateTime":"2026-05-24T10:00:00Z","content":"done task","visibility":"PRIVATE","state":"ARCHIVED","tags":[],"pinned":false}
                """.data(using: .utf8)!
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
            }
        }

        let processor = QueueProcessor(queue: queue, client: client)
        await processor.processAll()
        XCTAssertEqual(queue.pendingCount, 0)
        XCTAssertEqual(requestCount, 2)
    }

    func testProcessFailureIncrementsRetryCount() async throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let queue = OfflineQueue(storageURL: url)
        queue.enqueue(.create(content: "fail", visibility: .private, archiveAfterCreate: false))

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let auth = MemosAuth(
            service: "com.meowout.memos.test-\(UUID().uuidString)",
            baseURLKey: "memosBaseURL-test-\(UUID().uuidString)")
        try auth.configure(baseURL: URL(string: "https://memos.test")!, pat: "memos_pat_test")
        let client = MemosClient(session: URLSession(configuration: config), auth: auth)

        MockURLProtocol.requestHandler = { request in
            return (HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!,
                    "{}".data(using: .utf8)!)
        }

        let processor = QueueProcessor(queue: queue, client: client)
        await processor.processAll()
        XCTAssertEqual(queue.pendingCount, 1)
        XCTAssertEqual(queue.pendingItems[0].retryCount, 1)
        XCTAssertNotNil(queue.pendingItems[0].lastError)
    }

    func testConcurrentProcessAllDoesNotDuplicateQueuedCreate() async throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let queue = OfflineQueue(storageURL: url)
        queue.enqueue(.create(content: "only once", visibility: .private, archiveAfterCreate: false))
        let client = try makeTestClient()

        let requestStarted = expectation(description: "first request started")
        requestStarted.expectedFulfillmentCount = 1
        let lock = NSLock()
        var requestCount = 0

        MockURLProtocol.requestHandler = { request in
            lock.lock()
            requestCount += 1
            let currentRequestCount = requestCount
            lock.unlock()

            if currentRequestCount == 1 {
                requestStarted.fulfill()
                Thread.sleep(forTimeInterval: 0.2)
            }

            let body = """
            {"name":"memos/1","creator":"users/1","createTime":"2026-05-24T10:00:00Z","updateTime":"2026-05-24T10:00:00Z","content":"only once","visibility":"PRIVATE","state":"NORMAL","tags":[],"pinned":false}
            """.data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }

        let processor = QueueProcessor(queue: queue, client: client)
        let firstProcessing = Task {
            await processor.processAll()
        }
        await fulfillment(of: [requestStarted], timeout: 1)
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await processor.processAll()
            }
            group.addTask {
                await firstProcessing.value
            }
        }

        let finalRequestCount = lock.withLock { requestCount }
        XCTAssertEqual(finalRequestCount, 1)
        XCTAssertEqual(queue.pendingCount, 0)
    }
}
