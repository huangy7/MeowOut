import Foundation
import Combine

@MainActor
public class SnippetStore: ObservableObject {
    public static let shared = SnippetStore()

    @Published public var snippets: [Snippet] = [] {
        didSet {
            saveSubject.send()
        }
    }

    @Published public var customCategories: [String] = [] {
        didSet {
            saveSubject.send()
        }
    }

    private var cancellables = Set<AnyCancellable>()
    private let saveSubject = PassthroughSubject<Void, Never>()

    // Immutable storage URLs (nonisolated by default, safe to read from background thread)
    internal let storageURL: URL
    internal let categoriesStorageURL: URL

    // Serial background queue to serialize all writes and prevent race conditions
    private let saveQueue = DispatchQueue(label: "com.meowout.SnippetStore.save", qos: .background)

    // Internal initializer accepting a custom URL for testing
    internal init(storageURL: URL) {
        self.storageURL = storageURL
        let baseName = storageURL.deletingPathExtension().lastPathComponent
        self.categoriesStorageURL = storageURL
            .deletingLastPathComponent()
            .appendingPathComponent("\(baseName).categories.json")

        // Load initial snippets directly to avoid triggering didSet during initialization
        let fileManager = FileManager.default
        let directoryURL = storageURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directoryURL.path) {
            try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
        }

        var loadedSnippets: [Snippet] = []
        if fileManager.fileExists(atPath: storageURL.path) {
            do {
                let data = try Data(contentsOf: storageURL)
                loadedSnippets = try JSONDecoder().decode([Snippet].self, from: data)
            } catch {
                print("SnippetStore load failed: \(error)")
            }
        } else {
            loadedSnippets = [
                Snippet(title: "邮箱", content: "example@example.com"),
                Snippet(title: "手机号", content: "13800138000"),
                Snippet(title: "颜文字", content: "(╯°□°)╯︵ ┻━┻"),
                Snippet(title: "喝水提醒", content: "工作辛苦啦，起来喝杯水吧！🍵")
            ]
        }

        var seenIds = Set<UUID>()
        var uniqueSnippets: [Snippet] = []
        var hasDeduplicated = false
        for var snippet in loadedSnippets {
            if seenIds.contains(snippet.id) {
                snippet.id = UUID()
                hasDeduplicated = true
            }
            seenIds.insert(snippet.id)
            uniqueSnippets.append(snippet)
        }
        self.snippets = uniqueSnippets

        var loadedCategories: [String] = []
        if fileManager.fileExists(atPath: categoriesStorageURL.path) {
            do {
                let data = try Data(contentsOf: categoriesStorageURL)
                let decoded = try JSONDecoder().decode([String].self, from: data)
                loadedCategories = Self.normalizedCategoryList(decoded)
            } catch {
                print("SnippetStore categories load failed: \(error)")
                loadedCategories = Self.normalizedCategoryList(uniqueSnippets.map(\.category))
            }
        } else {
            loadedCategories = Self.normalizedCategoryList(uniqueSnippets.map(\.category))
        }
        self.customCategories = loadedCategories

        if hasDeduplicated {
            Self.saveToDisk(uniqueSnippets, to: storageURL)
        }

        // Setup debounced save subscription
        saveSubject
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                let snippetsToSave = self.snippets
                let categoriesToSave = self.customCategories
                let snippetsURL = self.storageURL
                let categoriesURL = self.categoriesStorageURL
                self.saveQueue.async {
                    Self.saveToDisk(snippetsToSave, to: snippetsURL)
                    Self.saveCategoriesToDisk(categoriesToSave, to: categoriesURL)
                }
            }
            .store(in: &cancellables)
    }

    private convenience init() {
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDirectoryURL = appSupportURL.appendingPathComponent("MeowOut", isDirectory: true)
        let fileURL = appDirectoryURL.appendingPathComponent("snippets.json")
        self.init(storageURL: fileURL)
    }

    // Static helpers to write data to disk safely from background thread
    private nonisolated static func saveToDisk(_ snippetsToSave: [Snippet], to url: URL) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(snippetsToSave)
            try data.write(to: url, options: .atomic)
        } catch {
            print("SnippetStore save failed: \(error)")
        }
    }

    private nonisolated static func saveCategoriesToDisk(_ categoriesToSave: [String], to url: URL) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(categoriesToSave)
            try data.write(to: url, options: .atomic)
        } catch {
            print("SnippetStore categories save failed: \(error)")
        }
    }

    private nonisolated static func normalizedCustomCategory(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed != KeyDropConstants.categoryAll,
              trimmed != KeyDropConstants.categoryUncategorized else {
            return nil
        }
        return trimmed
    }

    private nonisolated static func normalizedCategoryList(_ rawList: [String]) -> [String] {
        Array(Set(rawList.compactMap(normalizedCustomCategory))).sorted()
    }

    private var mergedCustomCategories: [String] {
        Self.normalizedCategoryList(customCategories + snippets.map(\.category))
    }

    public var managerCategories: [String] {
        var result = [KeyDropConstants.categoryAll] + mergedCustomCategories
        if snippets.contains(where: { $0.category == KeyDropConstants.categoryUncategorized || $0.category.isEmpty }) {
            result.append(KeyDropConstants.categoryUncategorized)
        }
        return result
    }

    public var editableCategories: [String] {
        mergedCustomCategories + [KeyDropConstants.categoryUncategorized]
    }

    public func snippetCount(in category: String) -> Int {
        if category == KeyDropConstants.categoryAll {
            return snippets.count
        }
        return snippets.filter { $0.category == category }.count
    }

    private func ensureCustomCategoryRecorded(_ raw: String) {
        guard let normalized = Self.normalizedCustomCategory(raw) else { return }
        if !customCategories.contains(normalized) {
            customCategories = (customCategories + [normalized]).sorted()
        }
    }

    @discardableResult
    public func addCategory(_ rawName: String) -> String? {
        guard let normalized = Self.normalizedCustomCategory(rawName) else { return nil }
        if !customCategories.contains(normalized) {
            customCategories = (customCategories + [normalized]).sorted()
        }
        return normalized
    }

    public func add(snippet: Snippet) {
        ensureCustomCategoryRecorded(snippet.category)
        snippets.append(snippet)
    }

    public func update(snippet: Snippet) {
        ensureCustomCategoryRecorded(snippet.category)
        if let index = snippets.firstIndex(where: { $0.id == snippet.id }) {
            let existing = snippets[index]
            var next = snippet
            if existing.title != snippet.title ||
                existing.content != snippet.content ||
                existing.category != snippet.category {
                next.updatedAt = Date()
            }
            snippets[index] = next
        }
    }

    public func delete(snippet: Snippet) {
        snippets.removeAll(where: { $0.id == snippet.id })
    }

    public func renameCategory(oldName: String, newName: String) {
        guard oldName != KeyDropConstants.categoryAll,
              let normalizedNew = Self.normalizedCustomCategory(newName),
              oldName != normalizedNew else {
            return
        }

        var updatedSnippets = snippets
        var didChangeSnippets = false
        for i in 0..<updatedSnippets.count {
            if updatedSnippets[i].category == oldName {
                updatedSnippets[i].category = normalizedNew
                didChangeSnippets = true
            }
        }
        if didChangeSnippets {
            snippets = updatedSnippets
        }

        var nextCategories = customCategories.filter { $0 != oldName }
        if !nextCategories.contains(normalizedNew) {
            nextCategories.append(normalizedNew)
        }
        let sortedCategories = nextCategories.sorted()
        if sortedCategories != customCategories {
            customCategories = sortedCategories
        }
    }

    public func deleteCategory(name: String, deleteSnippets: Bool) {
        guard name != KeyDropConstants.categoryAll,
              name != KeyDropConstants.categoryUncategorized else {
            return
        }

        let filteredCategories = customCategories.filter { $0 != name }
        if filteredCategories != customCategories {
            customCategories = filteredCategories
        }

        if deleteSnippets {
            let remaining = snippets.filter { $0.category != name }
            if remaining.count != snippets.count {
                snippets = remaining
            }
        } else {
            var updatedSnippets = snippets
            var didChange = false
            for i in 0..<updatedSnippets.count {
                if updatedSnippets[i].category == name {
                    updatedSnippets[i].category = KeyDropConstants.categoryUncategorized
                    didChange = true
                }
            }
            if didChange {
                snippets = updatedSnippets
            }
        }
    }

    public func moveSnippet(id: UUID, toOffset offset: Int, inFilteredList filtered: [Snippet]) {
        guard offset >= 0, !filtered.isEmpty else { return }
        guard let sourceIndex = snippets.firstIndex(where: { $0.id == id }) else { return }
        let item = snippets[sourceIndex]

        if offset < filtered.count {
            let targetId = filtered[offset].id
            if targetId == id { return }
            guard let targetIndex = snippets.firstIndex(where: { $0.id == targetId }) else { return }
            if targetIndex == sourceIndex { return }
            snippets.remove(at: sourceIndex)
            let newTargetIndex = snippets.firstIndex(where: { $0.id == targetId }) ?? snippets.count
            snippets.insert(item, at: newTargetIndex)
        } else {
            guard let lastId = filtered.last?.id else { return }
            if lastId == id { return }
            guard snippets.contains(where: { $0.id == lastId }) else { return }
            snippets.remove(at: sourceIndex)
            let newLastIndex = snippets.firstIndex(where: { $0.id == lastId }) ?? (snippets.count - 1)
            snippets.insert(item, at: newLastIndex + 1)
        }
    }
}
