import XCTest
@testable import MeowOut

@MainActor
final class UpdateNotificationTests: XCTestCase {
    func testPendingUpdateCoversAvailableAndReadyToInstall() {
        let url = URL(string: "https://example.com/MeowOut.dmg")!

        XCTAssertTrue(UpdateStatus.available(version: "1.1.0", notes: "", url: url).hasPendingUpdate)
        XCTAssertTrue(UpdateStatus.readyToInstall(version: "1.1.0", dmgPath: "/tmp/MeowOut-Update-1.1.0.dmg").hasPendingUpdate)
        XCTAssertFalse(UpdateStatus.idle.hasPendingUpdate)
        XCTAssertFalse(UpdateStatus.checking.hasPendingUpdate)
        XCTAssertFalse(UpdateStatus.downloading(progress: 0.5).hasPendingUpdate)
        XCTAssertFalse(UpdateStatus.error("failed").hasPendingUpdate)
    }

    func testLastNotifiedUpdateVersionPersists() {
        UserDefaults.standard.removeObject(forKey: "lastNotifiedUpdateVersion")

        let state = AppState()
        XCTAssertNil(state.lastNotifiedUpdateVersion)

        state.lastNotifiedUpdateVersion = "1.1.0"
        XCTAssertEqual(AppState().lastNotifiedUpdateVersion, "1.1.0")

        UserDefaults.standard.removeObject(forKey: "lastNotifiedUpdateVersion")
    }

    func testResetUpdateReminderMemoryClearsStoredVersion() {
        let state = AppState()
        state.lastNotifiedUpdateVersion = "1.1.0"

        state.resetUpdateReminderMemory()

        XCTAssertNil(state.lastNotifiedUpdateVersion)
        UserDefaults.standard.removeObject(forKey: "lastNotifiedUpdateVersion")
    }

    func testUpdateInteractionBubbleLocksUntilDismissed() {
        let state = PetState()
        state.showUpdateBubble(text: "Update available", version: "1.1.0")

        XCTAssertEqual(state.bubbleText, "Update available")
        XCTAssertTrue(state.bubbleVisible)
        XCTAssertTrue(state.isBubbleLocked)
        XCTAssertEqual(state.updateInteraction?.version, "1.1.0")

        state.dismissUpdateBubble()

        XCTAssertFalse(state.bubbleVisible)
        XCTAssertFalse(state.isBubbleLocked)
        XCTAssertNil(state.updateInteraction)
    }

    func testSettingsWindowOpenerIsAttachedToPersistentTrayLabel() throws {
        let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let appSource = try String(
            contentsOf: projectRoot.appendingPathComponent("Sources/MeowOut/MeowOutApp.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(appSource.contains(".background(WindowOpener())"))
    }
}
