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
        XCTAssertNil(snippet.createdAt)
        XCTAssertNil(snippet.updatedAt)
    }

    func testSnippetTimestampsCodableRoundTrip() throws {
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let updated = Date(timeIntervalSince1970: 1_700_003_600)
        let snippet = Snippet(
            title: "Timed",
            content: "Body",
            category: "工作",
            createdAt: created,
            updatedAt: updated
        )

        let data = try JSONEncoder().encode(snippet)
        let decoded = try JSONDecoder().decode(Snippet.self, from: data)
        XCTAssertEqual(decoded.createdAt, created)
        XCTAssertEqual(decoded.updatedAt, updated)
    }

    @MainActor
    func testSnippetStoreUpdateRefreshesUpdatedAt() {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MeowOutTests-timestamp-\(UUID().uuidString).json")
        let store = SnippetStore(storageURL: tempURL)
        defer {
            try? FileManager.default.removeItem(at: tempURL)
            try? FileManager.default.removeItem(at: store.categoriesStorageURL)
        }

        let past = Date(timeIntervalSince1970: 1_700_000_000)
        let original = Snippet(title: "Old", content: "Body", category: "工作", createdAt: past, updatedAt: past)
        store.snippets = [original]

        var edited = original
        edited.content = "Updated Body"
        store.update(snippet: edited)

        let stored = store.snippets.first(where: { $0.id == original.id })
        XCTAssertEqual(stored?.createdAt, past)
        XCTAssertNotNil(stored?.updatedAt)
        XCTAssertGreaterThan(stored?.updatedAt ?? past, past)
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
        
        let emptyZh = I18n.localized("keydrop_panel_empty", language: .zhHans)
        let emptyEn = I18n.localized("keydrop_panel_empty", language: .en)
        XCTAssertEqual(emptyZh, "尚无常用语，请在设置中添加")
        XCTAssertEqual(emptyEn, "No snippets yet, add them in Settings")
        
        let noMatchesZh = I18n.localized("keydrop_panel_no_matches", language: .zhHans)
        let noMatchesEn = I18n.localized("keydrop_panel_no_matches", language: .en)
        XCTAssertEqual(noMatchesZh, "无匹配结果")
        XCTAssertEqual(noMatchesEn, "No matching results")
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
        
        // Deduplicated UUIDs should be persisted to disk so future loads are stable
        let reloadedData = try Data(contentsOf: tempFileURL)
        let reloadedSnippets = try JSONDecoder().decode([Snippet].self, from: reloadedData)
        XCTAssertEqual(reloadedSnippets.count, 2)
        XCTAssertNotEqual(reloadedSnippets[0].id, reloadedSnippets[1].id, "Persisted disk file must not have duplicate UUIDs")
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
    
    @MainActor
    func testPanelViewModelCategoryAndSearchChangeMaintainsValidSelection() {
        let store = SnippetStore.shared
        let originalSnippets = store.snippets
        defer { store.snippets = originalSnippets }
        
        let sWork1 = Snippet(title: "Work 1", content: "w1", category: "Work")
        let sWork2 = Snippet(title: "Work 2", content: "w2", category: "Work")
        let sLife = Snippet(title: "Life 1", content: "l1", category: "Life")
        store.snippets = [sWork1, sWork2, sLife]
        
        let viewModel = PanelViewModel()
        viewModel.selectedCategory = KeyDropConstants.categoryAll
        XCTAssertEqual(viewModel.filteredSnippets.count, 3)
        
        // Select index 2 (sLife)
        viewModel.selectIndex(2, scroll: false)
        XCTAssertEqual(viewModel.selectedIndex, 2)
        XCTAssertEqual(viewModel.selectedSnippetId, sLife.id)
        
        // Switch to "Life" category which only has 1 item
        viewModel.selectedCategory = "Life"
        XCTAssertEqual(viewModel.filteredSnippets.count, 1)
        // Selection must be reset to index 0 or safely clamped, not dangling at index 2
        XCTAssertEqual(viewModel.selectedIndex, 0)
        XCTAssertEqual(viewModel.selectedSnippetId, sLife.id)
        XCTAssertNotNil(viewModel.selectedSnippet)
        
        // Switch to "Work" category (2 items)
        viewModel.selectedCategory = "Work"
        XCTAssertEqual(viewModel.selectedIndex, 0)
        XCTAssertEqual(viewModel.selectedSnippetId, sWork1.id)
        
        // Move selection to index 1
        viewModel.moveSelection(up: false)
        XCTAssertEqual(viewModel.selectedIndex, 1)
        XCTAssertEqual(viewModel.selectedSnippetId, sWork2.id)
        
        // Update searchText directly to a query matching only 1 item
        viewModel.searchText = "Work 1"
        XCTAssertEqual(viewModel.filteredSnippets.count, 1)
        XCTAssertEqual(viewModel.selectedIndex, 0)
        XCTAssertEqual(viewModel.selectedSnippetId, sWork1.id)
    }
    
    func testSnippetStoreMoveSnippetInvalidOffsetSafety() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
        let tempFileURL = tempDirectory.appendingPathComponent("MeowOutTests-invalid-offset-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempFileURL) }
        
        let store = await SnippetStore(storageURL: tempFileURL)
        await MainActor.run {
            store.snippets.removeAll()
        }
        let s0 = Snippet(title: "Item 0", content: "0")
        let s1 = Snippet(title: "Item 1", content: "1")
        await store.add(snippet: s0)
        await store.add(snippet: s1)
        
        let list = await store.snippets
        // Negative offset should not crash
        await store.moveSnippet(id: s0.id, toOffset: -1, inFilteredList: list)
        // Empty list should not crash
        await store.moveSnippet(id: s0.id, toOffset: 0, inFilteredList: [])
        
        let after = await store.snippets
        XCTAssertEqual(after.map(\.title), ["Item 0", "Item 1"])
    }

    @MainActor
    func testAddCategoryCreatesEmptyCategoryWithoutAddingSnippet() {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MeowOutTests-add-cat-\(UUID().uuidString).json")
        let store = SnippetStore(storageURL: tempURL)
        defer {
            try? FileManager.default.removeItem(at: tempURL)
            try? FileManager.default.removeItem(at: store.categoriesStorageURL)
        }

        store.snippets.removeAll()

        let added = store.addCategory("  开发  ")
        XCTAssertEqual(added, "开发")
        XCTAssertTrue(store.snippets.isEmpty, "Adding a category must not create a placeholder snippet")
        XCTAssertEqual(store.customCategories, ["开发"])
        XCTAssertEqual(store.managerCategories, [KeyDropConstants.categoryAll, "开发"])
        XCTAssertEqual(store.editableCategories, ["开发", KeyDropConstants.categoryUncategorized])

        // Duplicate returns canonical name without duplicating entry
        XCTAssertEqual(store.addCategory("开发"), "开发")
        XCTAssertEqual(store.customCategories, ["开发"])

        // Reserved or empty names are rejected
        XCTAssertNil(store.addCategory("   "))
        XCTAssertNil(store.addCategory(KeyDropConstants.categoryAll))
        XCTAssertNil(store.addCategory(KeyDropConstants.categoryUncategorized))
    }

    func testCustomCategoriesPersistAcrossReload() async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MeowOutTests-persist-cat-\(UUID().uuidString).json")
        let store = await SnippetStore(storageURL: tempURL)
        let categoriesURL = await store.categoriesStorageURL
        defer {
            try? FileManager.default.removeItem(at: tempURL)
            try? FileManager.default.removeItem(at: categoriesURL)
        }

        await MainActor.run {
            store.snippets.removeAll()
            _ = store.addCategory("工作")
            _ = store.addCategory("开发")
        }

        // Wait for 300ms debounce + background write
        try await Task.sleep(nanoseconds: 550_000_000)

        let reloaded = await SnippetStore(storageURL: tempURL)
        let reloadedCategories = await reloaded.customCategories
        let reloadedManagerCategories = await reloaded.managerCategories
        XCTAssertEqual(reloadedCategories, ["工作", "开发"])
        XCTAssertEqual(reloadedManagerCategories, [KeyDropConstants.categoryAll, "工作", "开发"])
    }

    @MainActor
    func testLegacySnippetsSeedCustomCategoriesOnFirstLoad() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MeowOutTests-legacy-cat-\(UUID().uuidString).json")
        let legacySnippet = Snippet(title: "Standup", content: "Yesterday / Today", category: "工作")
        let data = try JSONEncoder().encode([legacySnippet])
        try data.write(to: tempURL)

        let store = SnippetStore(storageURL: tempURL)
        defer {
            try? FileManager.default.removeItem(at: tempURL)
            try? FileManager.default.removeItem(at: store.categoriesStorageURL)
        }

        XCTAssertEqual(store.customCategories, ["工作"])

        // Deleting the only snippet in the category should keep the category intact
        store.delete(snippet: legacySnippet)
        XCTAssertTrue(store.snippets.isEmpty)
        XCTAssertTrue(store.managerCategories.contains("工作"))
        XCTAssertEqual(store.snippetCount(in: "工作"), 0)
    }

    @MainActor
    func testRenameCategoryUpdatesEmptyCategoryAndMergesDuplicates() {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MeowOutTests-rename-cat-\(UUID().uuidString).json")
        let store = SnippetStore(storageURL: tempURL)
        defer {
            try? FileManager.default.removeItem(at: tempURL)
            try? FileManager.default.removeItem(at: store.categoriesStorageURL)
        }

        store.snippets.removeAll()
        _ = store.addCategory("空分类")
        store.add(snippet: Snippet(title: "S1", content: "C1", category: "旧类"))
        store.add(snippet: Snippet(title: "S2", content: "C2", category: "目标类"))
        store.add(snippet: Snippet(title: "S3", content: "C3", category: KeyDropConstants.categoryUncategorized))

        // Rename empty category
        store.renameCategory(oldName: "空分类", newName: "新空分类")
        XCTAssertTrue(store.customCategories.contains("新空分类"))
        XCTAssertFalse(store.customCategories.contains("空分类"))

        // Merge into existing category
        store.renameCategory(oldName: "旧类", newName: "目标类")
        XCTAssertEqual(store.snippets.filter { $0.category == "目标类" }.count, 2)
        XCTAssertFalse(store.customCategories.contains("旧类"))
        XCTAssertEqual(store.customCategories.filter { $0 == "目标类" }.count, 1)

        // Rename uncategorized into a new named category
        store.renameCategory(oldName: KeyDropConstants.categoryUncategorized, newName: "已整理")
        XCTAssertEqual(store.snippets.filter { $0.category == "已整理" }.count, 1)
        XCTAssertEqual(store.snippets.filter { $0.category == KeyDropConstants.categoryUncategorized }.count, 0)
        XCTAssertTrue(store.customCategories.contains("已整理"))
    }

    @MainActor
    func testDeleteCategoryMoveToUncategorizedAndDeleteSnippetsModes() {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MeowOutTests-delete-cat-\(UUID().uuidString).json")
        let store = SnippetStore(storageURL: tempURL)
        defer {
            try? FileManager.default.removeItem(at: tempURL)
            try? FileManager.default.removeItem(at: store.categoriesStorageURL)
        }

        store.snippets.removeAll()
        store.add(snippet: Snippet(title: "KeepMe", content: "1", category: "工作"))
        store.add(snippet: Snippet(title: "RemoveMe", content: "2", category: "临时"))
        _ = store.addCategory("空类")

        // Delete empty category
        store.deleteCategory(name: "空类", deleteSnippets: false)
        XCTAssertFalse(store.customCategories.contains("空类"))

        // Delete category while preserving snippets -> moved to uncategorized
        store.deleteCategory(name: "工作", deleteSnippets: false)
        XCTAssertFalse(store.customCategories.contains("工作"))
        XCTAssertEqual(store.snippets.first(where: { $0.title == "KeepMe" })?.category, KeyDropConstants.categoryUncategorized)

        // Delete category AND snippets
        store.deleteCategory(name: "临时", deleteSnippets: true)
        XCTAssertFalse(store.customCategories.contains("临时"))
        XCTAssertNil(store.snippets.first(where: { $0.title == "RemoveMe" }))

        // Reserved categories cannot be deleted
        let countBefore = store.snippets.count
        store.deleteCategory(name: KeyDropConstants.categoryAll, deleteSnippets: true)
        store.deleteCategory(name: KeyDropConstants.categoryUncategorized, deleteSnippets: true)
        XCTAssertEqual(store.snippets.count, countBefore)
    }

    @MainActor
    func testPanelViewModelExcludesEmptyCustomCategories() {
        let store = SnippetStore.shared
        let originalSnippets = store.snippets
        let originalCustomCategories = store.customCategories
        defer {
            store.snippets = originalSnippets
            store.customCategories = originalCustomCategories
        }

        store.snippets = [Snippet(title: "Email", content: "a@b.com", category: "工作")]
        store.customCategories = ["工作", "空分类"]

        let viewModel = PanelViewModel()
        XCTAssertTrue(viewModel.categories.contains("工作"))
        XCTAssertFalse(viewModel.categories.contains("空分类"))
    }

    func testWorkspaceLocalizationKeysPresentInZhAndEn() {
        let keys = [
            "keydrop_shortcut_compact",
            "keydrop_search_full_placeholder",
            "keydrop_new_snippet_btn",
            "keydrop_draft_banner",
            "keydrop_draft_hint",
            "keydrop_draft_row_title",
            "keydrop_draft_row_badge",
            "keydrop_draft_row_subtitle",
            "keydrop_title_input_placeholder",
            "keydrop_content_input_placeholder",
            "keydrop_create_btn",
            "keydrop_autosaved",
            "keydrop_content_stats",
            "keydrop_move_to_category",
            "keydrop_delete_category",
            "keydrop_delete_category_title",
            "keydrop_delete_category_message",
            "keydrop_delete_category_keep_snippets",
            "keydrop_delete_category_with_snippets",
            "keydrop_delete_snippet_confirm_title",
            "keydrop_delete_snippet_confirm_message",
            "keydrop_discard_draft_title",
            "keydrop_discard_draft_message",
            "keydrop_discard_draft_btn",
            "keydrop_keep_editing_btn",
            "keydrop_empty_library_title",
            "keydrop_empty_library_desc",
            "keydrop_create_first_btn",
            "keydrop_empty_category_title",
            "keydrop_empty_category_desc",
            "keydrop_create_in_category_btn",
            "keydrop_clear_search_btn",
            "keydrop_select_prompt_title",
            "keydrop_select_prompt_desc",
            "keydrop_copy_content_btn",
            "keydrop_enabled_compact",
            "keydrop_meta_section_title",
            "keydrop_meta_created_at",
            "keydrop_meta_updated_at",
            "keydrop_total_count",
            "keydrop_filtered_count",
            "keydrop_saved_just_now",
            "keydrop_chars_count",
        ]

        for key in keys {
            let zh = I18n.localized(key, language: .zhHans)
            let en = I18n.localized(key, language: .en)
            XCTAssertNotEqual(zh, key, "Missing zh-Hans localization for \(key)")
            XCTAssertNotEqual(en, key, "Missing en localization for \(key)")
            XCTAssertFalse(zh.isEmpty)
            XCTAssertFalse(en.isEmpty)
        }
    }
}

