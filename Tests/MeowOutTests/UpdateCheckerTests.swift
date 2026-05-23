import XCTest
@testable import MeowOut

final class UpdateCheckerTests: XCTestCase {
    func testUpdateArtifactsUseStandardCachesDirectory() {
        XCTAssertTrue(UpdateChecker.downloadDestination(for: "1.1.0").path.contains("/Caches/MeowOut/"))
        XCTAssertEqual(UpdateChecker.downloadDestination(for: "1.1.0").lastPathComponent, "MeowOut-Update-1.1.0.dmg")
        XCTAssertTrue(UpdateChecker.installerScriptURL.path.contains("/Caches/MeowOut/"))
        XCTAssertEqual(UpdateChecker.installerScriptURL.lastPathComponent, "update-installer.sh")
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

    func testReadyToInstallRequiresExistingDMG() throws {
        let existing = URL(fileURLWithPath: "/tmp/meowout-existing-test.dmg")
        let missing = URL(fileURLWithPath: "/tmp/meowout-missing-test.dmg")
        let directory = URL(fileURLWithPath: "/tmp/meowout-directory-test.dmg")

        FileManager.default.createFile(atPath: existing.path, contents: Data(), attributes: nil)
        defer { try? FileManager.default.removeItem(at: existing) }
        try? FileManager.default.removeItem(at: missing)
        try? FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertTrue(UpdateChecker.isDownloadedDMGAvailable(at: existing.path))
        XCTAssertFalse(UpdateChecker.isDownloadedDMGAvailable(at: missing.path))
        XCTAssertFalse(UpdateChecker.isDownloadedDMGAvailable(at: directory.path))
    }

    func testSelectsDMGForPreferredArchitecture() {
        let assets: [[String: Any]] = [
            [
                "name": "MeowOut-1.2.0-Intel.dmg",
                "browser_download_url": "https://example.com/MeowOut-Intel.dmg"
            ],
            [
                "name": "MeowOut-1.2.0-AppleSilicon.dmg",
                "browser_download_url": "https://example.com/MeowOut-AppleSilicon.dmg"
            ]
        ]

        XCTAssertEqual(
            UpdateChecker.selectDMGAssetURL(from: assets, preferredArchitecture: "arm64")?.absoluteString,
            "https://example.com/MeowOut-AppleSilicon.dmg"
        )
        XCTAssertEqual(
            UpdateChecker.selectDMGAssetURL(from: assets, preferredArchitecture: "x86_64")?.absoluteString,
            "https://example.com/MeowOut-Intel.dmg"
        )
    }

    func testInstallScriptGuardsReplacementAndVerifiesVersion() {
        let script = UpdateChecker.installScriptContent(
            oldApp: "/Applications/MeowOut.app",
            newApp: "/Volumes/MeowOut 3/MeowOut.app",
            volume: "/Volumes/MeowOut 3",
            dmg: UpdateChecker.downloadDestination(for: "1.1.0").path,
            parentPID: 12345,
            expectedVersion: "1.1.0"
        )

        XCTAssertTrue(script.contains("fail \"Parent process still running after timeout\""))
        XCTAssertTrue(script.contains("/usr/libexec/PlistBuddy"))
        XCTAssertTrue(script.contains("UPDATED_VERSION="))
        XCTAssertTrue(script.contains("if [ \"$UPDATED_VERSION\" != \"$EXPECTED_VERSION\" ]; then"))
        XCTAssertTrue(script.contains("/bin/mv \"$STAGING\" \"$OLD_APP\""))
        XCTAssertTrue(script.contains("Update completed successfully"))
    }

    func testInstallScriptQuotesShellPaths() {
        let script = UpdateChecker.installScriptContent(
            oldApp: "/Applications/Bob's MeowOut.app",
            newApp: "/Volumes/Bob's MeowOut/MeowOut.app",
            volume: "/Volumes/Bob's MeowOut",
            dmg: "/Users/bob/Library/Caches/MeowOut/Bob's Update.dmg",
            parentPID: 12345,
            expectedVersion: "1.1.0-beta's"
        )

        XCTAssertTrue(script.contains("OLD_APP='/Applications/Bob'\\''s MeowOut.app'"))
        XCTAssertTrue(script.contains("NEW_APP='/Volumes/Bob'\\''s MeowOut/MeowOut.app'"))
        XCTAssertTrue(script.contains("VOLUME='/Volumes/Bob'\\''s MeowOut'"))
        XCTAssertTrue(script.contains("DMG='/Users/bob/Library/Caches/MeowOut/Bob'\\''s Update.dmg'"))
        XCTAssertTrue(script.contains("EXPECTED_VERSION='1.1.0-beta'\\''s'"))
    }
}
