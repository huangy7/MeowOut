import XCTest
@testable import MeowOut

final class BubblePositioningTests: XCTestCase {
    func testBubbleFrameAnchorsBottomAbovePetTop() {
        let petCenter = CGPoint(x: 200, y: 120)
        let petSize = CGSize(width: 60, height: 60)
        let bubbleSize = CGSize(width: 140, height: 42)

        let frame = CatOverlayController.bubbleFrame(
            petCenter: petCenter,
            petSize: petSize,
            bubbleSize: bubbleSize,
            gap: 10
        )

        XCTAssertEqual(frame.origin.x, 130)
        XCTAssertEqual(frame.origin.y, 160)
        XCTAssertEqual(frame.size.width, 140)
        XCTAssertEqual(frame.size.height, 42)
    }

    func testBubbleFrameKeepsBottomStableWhenBubbleHeightChanges() {
        let petCenter = CGPoint(x: 200, y: 120)
        let petSize = CGSize(width: 60, height: 60)

        let shortFrame = CatOverlayController.bubbleFrame(
            petCenter: petCenter,
            petSize: petSize,
            bubbleSize: CGSize(width: 140, height: 42),
            gap: 10
        )
        let tallFrame = CatOverlayController.bubbleFrame(
            petCenter: petCenter,
            petSize: petSize,
            bubbleSize: CGSize(width: 140, height: 82),
            gap: 10
        )

        XCTAssertEqual(shortFrame.origin.y, tallFrame.origin.y)
        XCTAssertEqual(shortFrame.minY, 160)
        XCTAssertEqual(tallFrame.minY, 160)
    }
}
