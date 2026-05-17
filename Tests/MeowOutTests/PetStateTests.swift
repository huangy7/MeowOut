import XCTest
@testable import MeowOut

@MainActor
final class PetStateTests: XCTestCase {
    func testShowLockedBubbleRaceCondition() async throws {
        let state = PetState()
        
        // 1. Call showLockedBubble with a short duration
        state.showLockedBubble("First", duration: 0.1)
        XCTAssertTrue(state.isBubbleLocked)
        XCTAssertEqual(state.bubbleText, "First")
        
        // 2. Wait a bit (less than 0.1s)
        try await Task.sleep(nanoseconds: 50_000_000) // 0.05s
        
        // 3. Call showLockedBubble again with another duration
        state.showLockedBubble("Second", duration: 0.1)
        XCTAssertTrue(state.isBubbleLocked)
        XCTAssertEqual(state.bubbleText, "Second")
        
        // 4. Wait until the first task would have finished (total > 0.1s but < 0.15s)
        try await Task.sleep(nanoseconds: 60_000_000) // 0.06s (Total 0.11s)
        
        // In the current implementation, the first task's timer will have expired
        // and it will set isBubbleLocked = false, even though the second task is still running.
        // We want isBubbleLocked to stay TRUE until the second task finishes.
        XCTAssertTrue(state.isBubbleLocked, "Bubble should still be locked by the second task")
        XCTAssertEqual(state.pose, .armsUp, "Pose should still be .armsUp")
        
        // 5. Wait for the second task to finish
        try await Task.sleep(nanoseconds: 50_000_000) // 0.05s (Total 0.16s)
        XCTAssertFalse(state.isBubbleLocked)
        XCTAssertEqual(state.pose, .rest)
    }
}
