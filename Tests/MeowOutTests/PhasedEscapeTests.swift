import XCTest
@testable import MeowOut

@MainActor
final class PhasedEscapeTests: XCTestCase {
    func testTapCountReset() async throws {
        let state = PetState()
        state.tapCount = 2
        
        state.showLockedBubble("Test", duration: 0.1)
        XCTAssertEqual(state.tapCount, 2)
        
        // Wait for bubble to disappear
        try await Task.sleep(nanoseconds: 150_000_000) // 0.15s
        
        XCTAssertEqual(state.tapCount, 0, "tapCount should reset to 0 after bubble expires")
    }
    
    func testPhasedEscapeQuotes() {
        // Test progress quotes (index 1)
        let progressQuote = DialogueManager.phasedEscapeQuotes(personality: .strict, language: .en, current: 1, target: 3)
        XCTAssertTrue(progressQuote.contains("1/3"))
        XCTAssertTrue(progressQuote.contains("Hands off"))
        
        // Test progress quotes (index 2)
        let progressQuote2 = DialogueManager.phasedEscapeQuotes(personality: .strict, language: .en, current: 2, target: 3)
        XCTAssertTrue(progressQuote2.contains("2/3"))
        XCTAssertTrue(progressQuote2.contains("No escape"))
        
        // Test give up quotes
        let giveupQuote = DialogueManager.phasedEscapeQuotes(personality: .strict, language: .en, current: 3, target: 3)
        XCTAssertTrue(giveupQuote.contains("Not another time"))
    }
}
