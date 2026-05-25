import XCTest
@testable import MemosKit

final class MemosAuthTests: XCTestCase {

    private func makeAuth() -> MemosAuth {
        MemosAuth(
            service: "com.meowout.memos.test-\(UUID().uuidString)",
            baseURLKey: "memosBaseURL-test-\(UUID().uuidString)"
        )
    }

    func testInitiallyNotConfigured() {
        let auth = makeAuth()
        XCTAssertFalse(auth.isConfigured)
        XCTAssertNil(auth.baseURL)
        XCTAssertNil(auth.pat)
    }

    func testConfigureStoresCredentials() throws {
        let auth = makeAuth()
        defer { auth.clear() }

        try auth.configure(baseURL: URL(string: "https://memos.example.com")!, pat: "memos_pat_test123")

        XCTAssertTrue(auth.isConfigured)
        XCTAssertEqual(auth.baseURL?.absoluteString, "https://memos.example.com")
        XCTAssertEqual(auth.pat, "memos_pat_test123")
    }

    func testClearRemovesCredentials() throws {
        let auth = makeAuth()
        try auth.configure(baseURL: URL(string: "https://memos.example.com")!, pat: "memos_pat_test123")

        auth.clear()

        XCTAssertFalse(auth.isConfigured)
        XCTAssertNil(auth.baseURL)
        XCTAssertNil(auth.pat)
    }
}
