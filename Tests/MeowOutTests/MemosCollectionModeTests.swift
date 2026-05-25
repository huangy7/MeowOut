import XCTest
@testable import MeowOut

final class MemosCollectionModeTests: XCTestCase {
    func testRootPagesIncludeArchivedBetweenMemosAndAttachments() {
        XCTAssertEqual(MemosRootPage.allCases.map(\.rawValue), ["memos", "archived", "attachments"])
        XCTAssertEqual(MemosRootPage.archived.title, I18n.localized("memos_action_archive"))
        XCTAssertEqual(MemosRootPage.archived.systemImage, "archivebox")
    }

    func testCollectionModeDefinesStateAndActions() {
        XCTAssertEqual(MemosCollectionMode.normal.memoState.rawValue, "NORMAL")
        XCTAssertTrue(MemosCollectionMode.normal.showsCreateButton)
        XCTAssertTrue(MemosCollectionMode.normal.allowsEditing)
        XCTAssertTrue(MemosCollectionMode.normal.allowsArchiving)
        XCTAssertFalse(MemosCollectionMode.normal.allowsRestoring)

        XCTAssertEqual(MemosCollectionMode.archived.memoState.rawValue, "ARCHIVED")
        XCTAssertFalse(MemosCollectionMode.archived.showsCreateButton)
        XCTAssertFalse(MemosCollectionMode.archived.allowsEditing)
        XCTAssertFalse(MemosCollectionMode.archived.allowsArchiving)
        XCTAssertTrue(MemosCollectionMode.archived.allowsRestoring)
    }
}
