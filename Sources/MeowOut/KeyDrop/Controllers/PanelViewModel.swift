import Foundation
import Combine

@MainActor
public class PanelViewModel: ObservableObject {
    @Published public var searchText: String = ""
    @Published public var selectedIndex: Int = 0
    @Published public var shouldScroll: Bool = false
    @Published public var selectedCategory: String = String(localized: "category_all", defaultValue: "全部")
    
    private var cancellables = Set<AnyCancellable>()
    
    public init() {
        SnippetStore.shared.$snippets
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
    
    public var categories: [String] {
        let list = SnippetStore.shared.snippets.map { $0.category }
        let unique = Array(Set(list)).sorted()
        return [String(localized: "category_all", defaultValue: "全部")] + unique
    }
    
    public var filteredSnippets: [Snippet] {
        let all = SnippetStore.shared.snippets
        let categoryFiltered = selectedCategory == String(localized: "category_all", defaultValue: "全部") ? all : all.filter { $0.category == selectedCategory }
        if searchText.isEmpty {
            return categoryFiltered
        }
        return categoryFiltered.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.content.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    public var selectedSnippet: Snippet? {
        let snippets = filteredSnippets
        guard !snippets.isEmpty, selectedIndex >= 0, selectedIndex < snippets.count else { return nil }
        return snippets[selectedIndex]
    }
    
    public func reset() {
        searchText = ""
        selectedCategory = String(localized: "category_all", defaultValue: "全部")
        selectIndex(0, scroll: true)
    }
    
    public func moveSelection(up: Bool) {
        let count = filteredSnippets.count
        guard count > 0 else { return }
        var nextIndex = selectedIndex
        if up {
            nextIndex = (selectedIndex - 1 + count) % count
        } else {
            nextIndex = (selectedIndex + 1) % count
        }
        selectIndex(nextIndex, scroll: true)
    }
    
    public func selectIndex(_ index: Int, scroll: Bool) {
        selectedIndex = index
        shouldScroll = scroll
    }
    
    public func snippet(at index: Int) -> Snippet? {
        let snippets = filteredSnippets
        guard index >= 0, index < snippets.count else { return nil }
        return snippets[index]
    }
    
    public func appendSearch(_ chars: String) {
        searchText.append(chars)
        selectIndex(0, scroll: true)
    }
    
    public func removeLastCharacter() {
        if !searchText.isEmpty {
            searchText.removeLast()
            selectIndex(0, scroll: true)
        }
    }
}
