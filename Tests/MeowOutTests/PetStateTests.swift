import XCTest
@testable import MeowOut

@MainActor
final class PetStateTests: XCTestCase {
    func testShowLockedBubbleRaceCondition() async throws {
        let state = PetState()

        // The first lock expires before the second one, so this exercises the guard that a
        // cancelled task must not unlock the bubble. The two calls are deliberately not
        // separated by a sleep: that guarantees the first task is still pending when the
        // second call cancels it. A fixed sleep here would, under CI scheduling jitter,
        // let the first lock expire on its own and bypass the very race being covered.
        state.showLockedBubble("First", duration: 0.2)
        XCTAssertTrue(state.isBubbleLocked)
        XCTAssertEqual(state.bubbleText, "First")

        state.showLockedBubble("Second", duration: 2.0)
        XCTAssertTrue(state.isBubbleLocked)
        XCTAssertEqual(state.bubbleText, "Second")

        // Past the first lock's expiry the bubble must still be held by the second lock.
        // CI runners overshoot Task.sleep by hundreds of milliseconds, so wait on wall-clock
        // time instead of a fixed sleep, and keep the second lock (2s) far from this instant.
        let pastFirstExpiry = Date().addingTimeInterval(0.4)
        while Date() < pastFirstExpiry {
            try await Task.sleep(nanoseconds: 20_000_000) // 20ms
        }
        XCTAssertTrue(state.isBubbleLocked, "Bubble should still be locked by the second task")
        XCTAssertEqual(state.pose, .armsUp, "Pose should still be .armsUp")

        // The second lock should release on its own.
        let unlockDeadline = Date().addingTimeInterval(5.0)
        while state.isBubbleLocked && Date() < unlockDeadline {
            try await Task.sleep(nanoseconds: 20_000_000) // 20ms
        }
        XCTAssertFalse(state.isBubbleLocked)
        XCTAssertEqual(state.pose, .rest)
    }
}
