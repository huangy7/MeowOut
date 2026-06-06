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

    func testNewQuickToolsSerialization() throws {
        let tools: [QuickTool] = [
            .builtIn(.memosQuickCapture),
            .builtIn(.memosOpenBrowser),
            .builtIn(.breathing)
        ]
        let data = try JSONEncoder().encode(tools)
        let decoded = try JSONDecoder().decode([QuickTool].self, from: data)
        XCTAssertEqual(decoded.count, 3)
        if case .builtIn(let type0) = decoded[0] {
            XCTAssertEqual(type0, .memosQuickCapture)
        } else { XCTFail() }
        if case .builtIn(let type1) = decoded[1] {
            XCTAssertEqual(type1, .memosOpenBrowser)
        } else { XCTFail() }
        if case .builtIn(let type2) = decoded[2] {
            XCTAssertEqual(type2, .breathing)
        } else { XCTFail() }
    }

    func testLauncherRingSerializationUsesOrderedTools() throws {
        let tools: [QuickTool] = [
            .builtIn(.keepAwake),
            .builtIn(.breathing),
            .appShortcut(id: UUID(), name: "Safari", path: "/Applications/Safari.app", bookmarkData: nil)
        ]
        let ring = LauncherRing(name: "Test Ring", tools: tools)
        let data = try JSONEncoder().encode([ring])
        let decoded = try JSONDecoder().decode([LauncherRing].self, from: data)

        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].name, "Test Ring")
        XCTAssertEqual(decoded[0].tools.count, 3)
        XCTAssertEqual(decoded[0].tools[0], .builtIn(.keepAwake))
        XCTAssertEqual(decoded[0].tools[1], .builtIn(.breathing))
        if case .appShortcut(_, let name, let path, _) = decoded[0].tools[2] {
            XCTAssertEqual(name, "Safari")
            XCTAssertEqual(path, "/Applications/Safari.app")
        } else {
            XCTFail("Expected app shortcut in third ring position")
        }
    }

    func testLauncherRingCapsToolsAtEight() {
        let longTools: [QuickTool] = Array(repeating: .builtIn(.keepAwake), count: 12)
        let ring = LauncherRing(name: "Long", tools: longTools)
        XCTAssertEqual(ring.tools.count, 8)
    }

    func testLauncherRingAllowsEmptyOrderedList() {
        let ring = LauncherRing(name: "Empty", tools: [])
        XCTAssertTrue(ring.tools.isEmpty)
    }
}
