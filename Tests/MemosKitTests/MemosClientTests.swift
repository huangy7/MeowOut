import XCTest
@testable import MemosKit

final class MemosClientTests: XCTestCase {

    private func makeClient() throws -> MemosClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        let auth = MemosAuth(
            service: "com.meowout.memos.test-\(UUID().uuidString)",
            baseURLKey: "memosBaseURL-test-\(UUID().uuidString)")
        try auth.configure(
            baseURL: URL(string: "https://memos.test")!,
            pat: "memos_pat_test123")
        return MemosClient(session: session, auth: auth)
    }

    func testThrowsNotConfiguredWhenNoAuth() async {
        let auth = MemosAuth(
            service: "com.meowout.memos.test-\(UUID().uuidString)",
            baseURLKey: "memosBaseURL-test-\(UUID().uuidString)")
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let client = MemosClient(session: URLSession(configuration: config), auth: auth)

        do {
            _ = try await client.verifyConnection()
            XCTFail("Expected notConfigured error")
        } catch let error as MemosError {
            if case .notConfigured = error {} else {
                XCTFail("Expected notConfigured, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testAuthorizationHeaderAttached() async throws {
        let client = try makeClient()
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer memos_pat_test123")
            let body = """
            {"version":"0.28.0","mode":"prod"}
            """.data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }

        let profile = try await client.verifyConnection()
        XCTAssertEqual(profile.version, "0.28.0")
    }

    func testUnauthorizedErrorOn401() async throws {
        let client = try makeClient()
        MockURLProtocol.requestHandler = { request in
            return (HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!,
                    "{}".data(using: .utf8)!)
        }

        do {
            _ = try await client.verifyConnection()
            XCTFail("Expected unauthorized error")
        } catch let error as MemosError {
            if case .unauthorized = error {} else {
                XCTFail("Expected unauthorized, got \(error)")
            }
        }
    }

    func testServerErrorOnNon2xx() async throws {
        let client = try makeClient()
        MockURLProtocol.requestHandler = { request in
            return (HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!,
                    "{\"message\":\"internal\"}".data(using: .utf8)!)
        }

        do {
            _ = try await client.verifyConnection()
            XCTFail("Expected serverError")
        } catch let error as MemosError {
            if case .serverError(let code, _) = error {
                XCTAssertEqual(code, 500)
            } else { XCTFail("Expected serverError, got \(error)") }
        }
    }

    // MARK: - Endpoint Tests

    func testGetCurrentUser() async throws {
        let client = try makeClient()
        MockURLProtocol.requestHandler = { request in
            XCTAssertTrue(request.url!.path.hasSuffix("/api/v1/auth/me"))
            let body = """
            {"user":{"name":"users/1","username":"huangy","displayName":"Huang Y","avatarUrl":null,"role":"USER","state":"NORMAL"}}
            """.data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        let user = try await client.getCurrentUser()
        XCTAssertEqual(user.username, "huangy")
    }

    func testCreateMemo() async throws {
        let client = try makeClient()
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.url!.path.hasSuffix("/api/v1/memos"))
            let reqBody = try! JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            XCTAssertNil(reqBody["memo"])
            XCTAssertEqual(reqBody["content"] as? String, "test #灵感")
            XCTAssertEqual(reqBody["visibility"] as? String, "PRIVATE")
            let responseBody = """
            {"name":"memos/99","creator":"users/1","createTime":"2026-05-24T10:00:00Z","updateTime":"2026-05-24T10:00:00Z","content":"test #灵感","visibility":"PRIVATE","state":"NORMAL","tags":["灵感"],"pinned":false,"snippet":"test"}
            """.data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, responseBody)
        }
        let memo = try await client.createMemo(content: "test #灵感", visibility: .private)
        XCTAssertEqual(memo.id, "99")
        XCTAssertEqual(memo.tags, ["灵感"])
    }

    func testListMemosWithFilter() async throws {
        let client = try makeClient()
        MockURLProtocol.requestHandler = { request in
            let url = request.url!
            XCTAssertTrue(url.path.hasSuffix("/api/v1/memos"))
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            let items = components.queryItems ?? []
            XCTAssertTrue(items.contains(where: { $0.name == "state" && $0.value == "NORMAL" }))
            XCTAssertTrue(items.contains(where: { $0.name == "pageSize" && $0.value == "10" }))
            XCTAssertTrue(items.contains(where: { $0.name == "filter" && $0.value == "tag in [\"灵感\"]" }))
            let body = """
            {"memos":[],"nextPageToken":"page2"}
            """.data(using: .utf8)!
            return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        let response = try await client.listMemos(state: .normal, filter: "tag in [\"灵感\"]", pageSize: 10)
        XCTAssertEqual(response.memos.count, 0)
        XCTAssertEqual(response.nextPageToken, "page2")
    }

    func testUpdateMemoArchive() async throws {
        let client = try makeClient()
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "PATCH")
            XCTAssertTrue(request.url!.path.hasSuffix("/api/v1/memos/42"))
            let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
            XCTAssertTrue((components.queryItems ?? []).contains(where: { $0.name == "updateMask" && $0.value == "state" }))
            let reqBody = try! JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            XCTAssertNil(reqBody["memo"])
            XCTAssertNil(reqBody["updateMask"])
            XCTAssertEqual(reqBody["name"] as? String, "memos/42")
            XCTAssertEqual(reqBody["state"] as? String, "ARCHIVED")
            let responseBody = """
            {"name":"memos/42","creator":"users/1","createTime":"2026-05-24T10:00:00Z","updateTime":"2026-05-24T11:00:00Z","content":"done","visibility":"PRIVATE","state":"ARCHIVED","tags":[],"pinned":false}
            """.data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, responseBody)
        }
        let memo = try await client.updateMemo(name: "memos/42", state: .archived, updateMask: ["state"])
        XCTAssertEqual(memo.state, .archived)
    }

    func testDeleteMemo() async throws {
        let client = try makeClient()
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertTrue(request.url!.path.hasSuffix("/api/v1/memos/42"))
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    "{}".data(using: .utf8)!)
        }
        try await client.deleteMemo(name: "memos/42")
    }

    func testGetUserStats() async throws {
        let client = try makeClient()
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertTrue(request.url!.path.hasSuffix("/api/v1/users/1:getStats"))
            let body = """
            {"name":"users/1/stats","tagCount":{"灵感":2},"memoCreatedTimestamps":["2026-05-24T10:00:00Z"],"pinnedMemos":["memos/1"],"totalMemoCount":1}
            """.data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }

        let stats = try await client.getUserStats(userName: "users/1")
        XCTAssertEqual(stats.tagCount["灵感"], 2)
        XCTAssertEqual(stats.memoCreatedTimestamps.count, 1)
        XCTAssertEqual(stats.totalMemoCount, 1)
    }
}
