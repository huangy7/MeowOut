// Tests/MeowOutTests/SnippetTests.swift
import XCTest
import Combine
@testable import MeowOut

final class SnippetTests: XCTestCase {
    
    func testSnippetInitializationAndProperties() {
        let id = UUID()
        let snippet = Snippet(id: id, title: "Test Title", content: "Test Content")
        
        XCTAssertEqual(snippet.id, id)
        XCTAssertEqual(snippet.title, "Test Title")
        XCTAssertEqual(snippet.content, "Test Content")
        
        let defaultIdSnippet = Snippet(title: "Default ID", content: "Content")
        XCTAssertNotNil(defaultIdSnippet.id)
    }
    
    func testSnippetCodable() throws {
        let snippet = Snippet(title: "JSON Test", content: "JSON Content")
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let data = try encoder.encode(snippet)
        let decoded = try decoder.decode(Snippet.self, from: data)
        
        XCTAssertEqual(decoded.id, snippet.id)
        XCTAssertEqual(decoded.title, snippet.title)
        XCTAssertEqual(decoded.content, snippet.content)
    }
    
    func testSnippetStoreCRUD() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
        let tempFileURL = tempDirectory.appendingPathComponent("MeowOutTests-snippets-\(UUID().uuidString).json")
        
        // Ensure clean state (no file exists)
        if FileManager.default.fileExists(atPath: tempFileURL.path) {
            try? FileManager.default.removeItem(at: tempFileURL)
        }
        
        // Instantiate isolated store
        let store = await SnippetStore(storageURL: tempFileURL)
        
        // Defer cleanup of the temp file
        defer {
            try? FileManager.default.removeItem(at: tempFileURL)
        }
        
        // 1. Initial State / Load
        // Ensure snippets is populated with defaults when the file doesn't exist
        let initialSnippets = await store.snippets
        XCTAssertFalse(initialSnippets.isEmpty)
        let originalCount = initialSnippets.count
        
        // 2. Add Snippet
        let newSnippet = Snippet(title: "New Snippet", content: "New Content")
        await store.add(snippet: newSnippet)
        
        let snippetsAfterAdd = await store.snippets
        XCTAssertEqual(snippetsAfterAdd.count, originalCount + 1)
        XCTAssertTrue(snippetsAfterAdd.contains(where: { $0.id == newSnippet.id }))
        
        // 3. Update Snippet
        var updatedSnippet = newSnippet
        updatedSnippet.title = "Updated Title"
        updatedSnippet.content = "Updated Content"
        
        await store.update(snippet: updatedSnippet)
        
        let snippetsAfterUpdate = await store.snippets
        if let found = snippetsAfterUpdate.first(where: { $0.id == newSnippet.id }) {
            XCTAssertEqual(found.title, "Updated Title")
            XCTAssertEqual(found.content, "Updated Content")
        } else {
            XCTFail("Snippet not found after update")
        }
        
        // 4. Delete Snippet
        await store.delete(snippet: updatedSnippet)
        
        let snippetsAfterDelete = await store.snippets
        XCTAssertEqual(snippetsAfterDelete.count, originalCount)
        XCTAssertFalse(snippetsAfterDelete.contains(where: { $0.id == newSnippet.id }))
    }
    
    func testLocalizationsNoKeyDropParenthesis() {
        let textZh = I18n.localized("keydrop_enabled", language: .zhHans)
        let textEn = I18n.localized("keydrop_enabled", language: .en)
        XCTAssertFalse(textZh.contains("(KeyDrop)"))
        XCTAssertFalse(textEn.contains("(KeyDrop)"))
    }
    
    func testSnippetBackwardCompatibility() throws {
        let oldJson = """
        {
            "id": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
            "title": "Old Snippet",
            "content": "Old Content"
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        let snippet = try decoder.decode(Snippet.self, from: oldJson)
        XCTAssertEqual(snippet.title, "Old Snippet")
        XCTAssertEqual(snippet.category, "未分类")
    }
    
    func testSnippetWithCategory() throws {
        let snippet = Snippet(title: "Categorized", content: "Content", category: "Git")
        XCTAssertEqual(snippet.category, "Git")
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(snippet)
        let decoded = try decoder.decode(Snippet.self, from: data)
        XCTAssertEqual(decoded.category, "Git")
    }
    
    @MainActor
    func testPanelViewModelFiltering() {
        let store = SnippetStore.shared
        let originalSnippets = store.snippets
        defer { store.snippets = originalSnippets }
        
        store.snippets = [
            Snippet(title: "61.29", content: "Wangsu", category: "未分类"),
            Snippet(title: "11111", content: "11111", category: "111")
        ]
        
        let viewModel = PanelViewModel()
        XCTAssertEqual(viewModel.categories, [String(localized: "category_all", defaultValue: "全部"), "111", "未分类"])
        
        viewModel.selectedCategory = "111"
        let filtered = viewModel.filteredSnippets
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.title, "11111")
    }
    
    func testSnippetManagerLocalizations() {
        let titleZh = I18n.localized("keydrop_manager_title", language: .zhHans)
        let titleEn = I18n.localized("keydrop_manager_title", language: .en)
        XCTAssertEqual(titleZh, "常用语管理器")
        XCTAssertEqual(titleEn, "Phrase Manager")
        
        let descZh = I18n.localized("keydrop_manage_desc", language: .zhHans)
        let descEn = I18n.localized("keydrop_manage_desc", language: .en)
        XCTAssertTrue(descZh.contains("常用语"))
        XCTAssertTrue(descEn.contains("phrase"))
    }
}

