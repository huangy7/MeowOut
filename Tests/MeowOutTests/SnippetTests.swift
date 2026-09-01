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
    
    func testRenameCategory() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
        let tempFileURL = tempDirectory.appendingPathComponent("MeowOutTests-snippets-\(UUID().uuidString).json")
        
        if FileManager.default.fileExists(atPath: tempFileURL.path) {
            try? FileManager.default.removeItem(at: tempFileURL)
        }
        
        let store = await SnippetStore(storageURL: tempFileURL)
        defer {
            try? FileManager.default.removeItem(at: tempFileURL)
        }
        
        // Clear initial defaults for easier testing
        await MainActor.run {
            store.snippets.removeAll()
        }
        
        await store.add(snippet: Snippet(title: "Test 1", content: "1", category: "OldCat"))
        await store.add(snippet: Snippet(title: "Test 2", content: "2", category: "OldCat"))
        await store.add(snippet: Snippet(title: "Test 3", content: "3", category: "OtherCat"))
        
        await store.renameCategory(oldName: "OldCat", newName: "NewCat")
        
        let snippets = await store.snippets
        XCTAssertEqual(snippets.filter { $0.category == "NewCat" }.count, 2)
        XCTAssertEqual(snippets.filter { $0.category == "OldCat" }.count, 0)
        XCTAssertEqual(snippets.filter { $0.category == "OtherCat" }.count, 1)
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

    @MainActor
    func testPanelViewModelTreatsClipboardHistoryCategoryAsOrdinaryCategory() {
        let store = SnippetStore.shared
        let originalSnippets = store.snippets
        defer { store.snippets = originalSnippets }

        let workSnippet = Snippet(title: "Daily standup", content: "Project notes", category: "工作")
        let clipboardNamedSnippet = Snippet(title: "User category", content: "Plain phrase", category: "剪贴板历史")
        store.snippets = [workSnippet, clipboardNamedSnippet]

        let viewModel = PanelViewModel()
        XCTAssertEqual(viewModel.categories.filter { $0 == "剪贴板历史" }.count, 1)
        XCTAssertTrue(viewModel.categories.contains("工作"))

        viewModel.selectedCategory = "剪贴板历史"
        let filtered = viewModel.filteredSnippets
        XCTAssertEqual(filtered, [clipboardNamedSnippet])
    }

    func testKeyDropConstantsDoesNotDefineClipboardCategory() throws {
        let constantsRelativePath = "Sources/MeowOut/KeyDrop/Constants.swift"
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        var sourceURL = directory.appendingPathComponent(constantsRelativePath)

        while !FileManager.default.fileExists(atPath: sourceURL.path) {
            let parent = directory.deletingLastPathComponent()
            if parent.path == directory.path {
                XCTFail("Could not locate package root containing \(constantsRelativePath)")
                return
            }

            directory = parent
            sourceURL = directory.appendingPathComponent(constantsRelativePath)
        }

        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let declarationPattern = #"^\s*(?:public|internal|private|fileprivate)?\s*static\s+(?:let|var)\s+categoryClipboard\b"#
        let declarationRegex = try NSRegularExpression(pattern: declarationPattern)
        var isInsideBlockComment = false

        let matchingDeclarations = source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { line in
                var text = String(line)

                if isInsideBlockComment {
                    if text.contains("*/") {
                        isInsideBlockComment = false
                    }
                    return false
                }

                let trimmed = text.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("//") {
                    return false
                }
                if trimmed.hasPrefix("/*") {
                    isInsideBlockComment = !trimmed.contains("*/")
                    return false
                }
                if let commentStart = text.range(of: "//") {
                    text = String(text[..<commentStart.lowerBound])
                }

                let range = NSRange(text.startIndex..<text.endIndex, in: text)
                return declarationRegex.firstMatch(in: text, range: range) != nil
            }

        XCTAssertTrue(matchingDeclarations.isEmpty, "KeyDropConstants must not define categoryClipboard")
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
    
    @MainActor
    func testPanelViewModelSelectionAndSelectedSnippetId() {
        let store = SnippetStore.shared
        let originalSnippets = store.snippets
        defer { store.snippets = originalSnippets }
        
        let s1 = Snippet(title: "First", content: "1", category: "Test")
        let s2 = Snippet(title: "Second", content: "2", category: "Test")
        let s3 = Snippet(title: "Third", content: "3", category: "Test")
        store.snippets = [s1, s2, s3]
        
        let viewModel = PanelViewModel()
        viewModel.selectedCategory = "Test"
        
        // Initial selection should be index 0 (s1)
        XCTAssertEqual(viewModel.selectedIndex, 0)
        XCTAssertEqual(viewModel.selectedSnippetId, s1.id)
        
        // Move selection down
        viewModel.moveSelection(up: false)
        XCTAssertEqual(viewModel.selectedIndex, 1)
        XCTAssertEqual(viewModel.selectedSnippetId, s2.id)
        
        // Move selection down again
        viewModel.moveSelection(up: false)
        XCTAssertEqual(viewModel.selectedIndex, 2)
        XCTAssertEqual(viewModel.selectedSnippetId, s3.id)
        
        // Wrap around downwards
        viewModel.moveSelection(up: false)
        XCTAssertEqual(viewModel.selectedIndex, 0)
        XCTAssertEqual(viewModel.selectedSnippetId, s1.id)
        
        // Wrap around upwards
        viewModel.moveSelection(up: true)
        XCTAssertEqual(viewModel.selectedIndex, 2)
        XCTAssertEqual(viewModel.selectedSnippetId, s3.id)
        
        // Safe clamping on selectIndex
        viewModel.selectIndex(99, scroll: false)
        XCTAssertEqual(viewModel.selectedIndex, 2)
        XCTAssertEqual(viewModel.selectedSnippetId, s3.id)
        
        viewModel.selectIndex(-5, scroll: false)
        XCTAssertEqual(viewModel.selectedIndex, 0)
        XCTAssertEqual(viewModel.selectedSnippetId, s1.id)
        
        // Empty list behavior
        viewModel.searchText = "nonexistent_query_xyz"
        XCTAssertTrue(viewModel.filteredSnippets.isEmpty)
        XCTAssertNil(viewModel.selectedSnippetId)
    }
    
    func testSnippetStoreDeduplicationOnLoad() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
        let tempFileURL = tempDirectory.appendingPathComponent("MeowOutTests-dup-snippets-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempFileURL) }
        
        let duplicateUUID = UUID()
        let snippet1 = Snippet(id: duplicateUUID, title: "Title 1", content: "Content 1")
        let snippet2 = Snippet(id: duplicateUUID, title: "Title 2", content: "Content 2")
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode([snippet1, snippet2])
        try data.write(to: tempFileURL)
        
        let store = await SnippetStore(storageURL: tempFileURL)
        let loaded = await store.snippets
        
        XCTAssertEqual(loaded.count, 2)
        XCTAssertNotEqual(loaded[0].id, loaded[1].id, "Duplicate UUIDs must be deduplicated on load")
        XCTAssertEqual(loaded[0].title, "Title 1")
        XCTAssertEqual(loaded[1].title, "Title 2")
    }
    
    func testSnippetStoreMoveSnippet() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
        let tempFileURL = tempDirectory.appendingPathComponent("MeowOutTests-move-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempFileURL) }
        
        let store = await SnippetStore(storageURL: tempFileURL)
        await MainActor.run {
            store.snippets.removeAll()
        }
        
        let s0 = Snippet(title: "Item 0", content: "0")
        let s1 = Snippet(title: "Item 1", content: "1")
        let s2 = Snippet(title: "Item 2", content: "2")
        let s3 = Snippet(title: "Item 3", content: "3")
        
        await store.add(snippet: s0)
        await store.add(snippet: s1)
        await store.add(snippet: s2)
        await store.add(snippet: s3)
        
        let initialList = await store.snippets
        XCTAssertEqual(initialList.map(\.title), ["Item 0", "Item 1", "Item 2", "Item 3"])
        
        // Move Item 3 to index 0
        await store.moveSnippet(id: s3.id, toOffset: 0, inFilteredList: initialList)
        var current = await store.snippets
        XCTAssertEqual(current.map(\.title), ["Item 3", "Item 0", "Item 1", "Item 2"])
        
        // Move Item 3 before Item 2 (offset 3)
        await store.moveSnippet(id: s3.id, toOffset: 3, inFilteredList: current)
        current = await store.snippets
        XCTAssertEqual(current.map(\.title), ["Item 0", "Item 1", "Item 3", "Item 2"])
        
        // Move Item 3 to the very end (offset 4 == current.count)
        await store.moveSnippet(id: s3.id, toOffset: current.count, inFilteredList: current)
        current = await store.snippets
        XCTAssertEqual(current.map(\.title), ["Item 0", "Item 1", "Item 2", "Item 3"])
        
        // Move Item 0 to the end (offset == filtered.count)
        await store.moveSnippet(id: s0.id, toOffset: current.count, inFilteredList: current)
        current = await store.snippets
        XCTAssertEqual(current.map(\.title), ["Item 1", "Item 2", "Item 3", "Item 0"])
    }
}
