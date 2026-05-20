import XCTest
@testable import MeowOut

final class UpdateCheckerTests: XCTestCase {
    func testUpdateArtifactsUseStandardTmpDirectory() {
        XCTAssertEqual(
            UpdateChecker.downloadDestination(for: "1.1.0").path,
            "/tmp/MeowOut-Update-1.1.0.dmg"
        )
        XCTAssertEqual(
            UpdateChecker.installerScriptURL.path,
            "/tmp/meowout-upgrade.sh"
        )
    }

    func testUpdateCheckerDoesNotReadGlobalAppState() throws {
        let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let updateCheckerSource = try String(
            contentsOf: projectRoot.appendingPathComponent("Sources/MeowOut/UpdateChecker.swift"),
            encoding: .utf8
        )
        let appStateSource = try String(
            contentsOf: projectRoot.appendingPathComponent("Sources/MeowOut/AppState.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(updateCheckerSource.contains("AppState.shared"))
        XCTAssertFalse(appStateSource.contains("static let shared = AppState()"))
    }

    func testReadyToInstallRequiresExistingDMG() {
        let existing = URL(fileURLWithPath: "/tmp/meowout-existing-test.dmg")
        let missing = URL(fileURLWithPath: "/tmp/meowout-missing-test.dmg")

        FileManager.default.createFile(atPath: existing.path, contents: Data(), attributes: nil)
        defer { try? FileManager.default.removeItem(at: existing) }
        try? FileManager.default.removeItem(at: missing)

        XCTAssertTrue(UpdateChecker.isDownloadedDMGAvailable(at: existing.path))
        XCTAssertFalse(UpdateChecker.isDownloadedDMGAvailable(at: missing.path))
    }
}
