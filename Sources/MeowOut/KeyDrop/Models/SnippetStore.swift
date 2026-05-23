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
    
    private var cancellables = Set<AnyCancellable>()
    private let saveSubject = PassthroughSubject<Void, Never>()
    
    // Immutable storage URL (nonisolated by default, safe to read from background thread)
    internal let storageURL: URL
    
    // Serial background queue to serialize all writes and prevent race conditions
    private let saveQueue = DispatchQueue(label: "com.meowout.SnippetStore.save", qos: .background)
    
    // Internal initializer accepting a custom URL for testing
    internal init(storageURL: URL) {
        self.storageURL = storageURL
        
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
        
        self.snippets = loadedSnippets
        
        // Setup debounced save subscription
        saveSubject
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                let snippetsToSave = self.snippets
                let url = self.storageURL
                self.saveQueue.async {
                    Self.saveToDisk(snippetsToSave, to: url)
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
    
    // Static helper to write data to disk safely from background thread
    private static func saveToDisk(_ snippetsToSave: [Snippet], to url: URL) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(snippetsToSave)
            try data.write(to: url, options: .atomic)
        } catch {
            print("SnippetStore save failed: \(error)")
        }
    }
    
    public func add(snippet: Snippet) {
        snippets.append(snippet)
    }
    
    public func update(snippet: Snippet) {
        if let index = snippets.firstIndex(where: { $0.id == snippet.id }) {
            snippets[index] = snippet
        }
    }
    
    public func delete(snippet: Snippet) {
        snippets.removeAll(where: { $0.id == snippet.id })
    }
}
