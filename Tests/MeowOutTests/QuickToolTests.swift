import XCTest
@testable import MeowOut

final class QuickToolTests: XCTestCase {
    func testQuickToolSerialization() throws {
        let tools: [QuickTool] = [
            .builtIn(.keepAwake),
            .appShortcut(id: UUID(), name: "Safari", path: "/Applications/Safari.app", bookmarkData: nil)
        ]
        let data = try JSONEncoder().encode(tools)
        let decoded = try JSONDecoder().decode([QuickTool].self, from: data)
        XCTAssertEqual(decoded.count, 2)
        if case .builtIn(let type) = decoded[0] {
            XCTAssertEqual(type, .keepAwake)
        } else { XCTFail() }
        if case .appShortcut(_, let name, let path, _) = decoded[1] {
            XCTAssertEqual(name, "Safari")
            XCTAssertEqual(path, "/Applications/Safari.app")
        } else { XCTFail() }
    }
}
