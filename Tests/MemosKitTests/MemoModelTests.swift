import XCTest
@testable import MemosKit

final class MemoModelTests: XCTestCase {

    func testMemoIdParsedFromName() {
        let memo = Memo(
            name: "memos/42", creator: "users/1",
            createTime: Date(), updateTime: Date(),
            content: "test", visibility: .private, state: .normal,
            tags: [], pinned: false, snippet: nil, property: nil)
        XCTAssertEqual(memo.id, "42")
    }

    func testMemoVisibilityRoundTrip() throws {
        for vis in MemoVisibility.allCases {
            let data = try JSONEncoder().encode(vis)
            let decoded = try JSONDecoder().decode(MemoVisibility.self, from: data)
            XCTAssertEqual(decoded, vis)
        }
    }

    func testMemoStateRoundTrip() throws {
        let data = try JSONEncoder().encode(MemoState.archived)
        let decoded = try JSONDecoder().decode(MemoState.self, from: data)
        XCTAssertEqual(decoded, .archived)
    }

    func testMemoDecodingFromAPIJSON() throws {
        let json = """
        {
          "name": "memos/7",
          "creator": "users/1",
          "createTime": "2026-05-20T10:30:00.123Z",
          "updateTime": "2026-05-20T11:00:00Z",
          "content": "买菜 #待办",
          "visibility": "PRIVATE",
          "state": "NORMAL",
          "tags": ["待办"],
          "pinned": false,
          "snippet": "买菜",
          "property": {
            "hasLink": false,
            "hasTaskList": false,
            "hasCode": false,
            "hasIncompleteTasks": false
          }
        }
        """.data(using: .utf8)!

        let decoder = MemosDateCoding.makeDecoder()
        let memo = try decoder.decode(Memo.self, from: json)
        XCTAssertEqual(memo.id, "7")
        XCTAssertEqual(memo.creator, "users/1")
        XCTAssertEqual(memo.content, "买菜 #待办")
        XCTAssertEqual(memo.visibility, .private)
        XCTAssertEqual(memo.state, .normal)
        XCTAssertEqual(memo.tags, ["待办"])
        XCTAssertEqual(memo.pinned, false)
        XCTAssertEqual(memo.snippet, "买菜")
        XCTAssertEqual(memo.property?.hasLink, false)
    }

    func testListMemosResponseDecoding() throws {
        let json = """
        {
          "memos": [
            {
              "name": "memos/1",
              "creator": "users/1",
              "createTime": "2026-05-20T10:00:00Z",
              "updateTime": "2026-05-20T10:00:00Z",
              "content": "hello",
              "visibility": "PRIVATE",
              "state": "NORMAL",
              "tags": [],
              "pinned": false
            }
          ],
          "nextPageToken": "abc123"
        }
        """.data(using: .utf8)!

        let decoder = MemosDateCoding.makeDecoder()
        let response = try decoder.decode(ListMemosResponse.self, from: json)
        XCTAssertEqual(response.memos.count, 1)
        XCTAssertEqual(response.memos[0].id, "1")
        XCTAssertEqual(response.nextPageToken, "abc123")
    }

    func testDateDecodingWithAndWithoutFractionalSeconds() throws {
        let jsonWithFrac = """
        {"name":"memos/1","creator":"users/1","createTime":"2026-01-15T10:30:00.999Z","updateTime":"2026-01-15T10:30:00.999Z","content":"a","visibility":"PRIVATE","state":"NORMAL","tags":[],"pinned":false}
        """.data(using: .utf8)!

        let jsonWithoutFrac = """
        {"name":"memos/2","creator":"users/1","createTime":"2026-01-15T10:30:00Z","updateTime":"2026-01-15T10:30:00Z","content":"b","visibility":"PRIVATE","state":"NORMAL","tags":[],"pinned":false}
        """.data(using: .utf8)!

        let decoder = MemosDateCoding.makeDecoder()
        let memo1 = try decoder.decode(Memo.self, from: jsonWithFrac)
        let memo2 = try decoder.decode(Memo.self, from: jsonWithoutFrac)
        XCTAssertEqual(memo1.id, "1")
        XCTAssertEqual(memo2.id, "2")
    }
}
