import XCTest
@testable import MeowOut

final class QuickMemoDraftStoreTests: XCTestCase {
    func testSaveAndLoadDraft() throws {
        let defaults = UserDefaults(suiteName: "QuickMemoDraftStoreTests.\(UUID().uuidString)")!
        let store = QuickMemoDraftStore(defaults: defaults)

        store.save(QuickMemoDraft(content: "hello #tag", visibility: "PRIVATE"))

        let draft = try XCTUnwrap(store.load())
        XCTAssertEqual(draft.content, "hello #tag")
        XCTAssertEqual(draft.visibility, "PRIVATE")
    }

    func testClearRemovesDraft() {
        let defaults = UserDefaults(suiteName: "QuickMemoDraftStoreTests.\(UUID().uuidString)")!
        let store = QuickMemoDraftStore(defaults: defaults)

        store.save(QuickMemoDraft(content: "unsaved", visibility: "PUBLIC"))
        store.clear()

        XCTAssertNil(store.load())
    }

    func testEmptyContentDoesNotPersistDraft() {
        let defaults = UserDefaults(suiteName: "QuickMemoDraftStoreTests.\(UUID().uuidString)")!
        let store = QuickMemoDraftStore(defaults: defaults)

        store.save(QuickMemoDraft(content: "   \n", visibility: "PRIVATE"))

        XCTAssertNil(store.load())
    }
}
