import Foundation
import Combine

@MainActor
public class PanelViewModel: ObservableObject {
    @Published public var searchText: String = "" {
        didSet {
            guard searchText != oldValue else { return }
            selectIndex(0, scroll: false)
        }
    }
    @Published public var selectedIndex: Int = 0
    @Published public var shouldScroll: Bool = false
    @Published public var selectedCategory: String = KeyDropConstants.categoryAll {
        didSet {
            guard selectedCategory != oldValue else { return }
            selectIndex(0, scroll: false)
        }
    }
    
    public var isPanelVisible: Bool = false {
        didSet {
            if isPanelVisible && needsRefresh {
                needsRefresh = false
                objectWillChange.send()
            }
        }
    }
    private var needsRefresh = false
    
    private var cancellables = Set<AnyCancellable>()
    
    public init() {
        SnippetStore.shared.$snippets
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.clampSelection()
                if self.isPanelVisible {
                    self.objectWillChange.send()
                } else {
                    self.needsRefresh = true
                }
            }
            .store(in: &cancellables)
    }
    
    private func clampSelection() {
        let count = filteredSnippets.count
        guard count > 0 else {
            selectedIndex = 0
            return
        }
        selectedIndex = min(max(0, selectedIndex), count - 1)
    }
    
    public var categories: [String] {
        let list = SnippetStore.shared.snippets.map { $0.category }
        let unique = Array(Set(list)).sorted()
        return [KeyDropConstants.categoryAll] + unique
    }
    
    public var filteredSnippets: [Snippet] {
        let all = SnippetStore.shared.snippets
        let categoryFiltered = selectedCategory == KeyDropConstants.categoryAll ? all : all.filter { $0.category == selectedCategory }
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
        guard !snippets.isEmpty else { return nil }
        let safeIndex = min(max(0, selectedIndex), snippets.count - 1)
        return snippets[safeIndex]
    }
    
    public var selectedSnippetId: UUID? {
        selectedSnippet?.id
    }
    
    public func reset() {
        searchText = ""
        selectedCategory = KeyDropConstants.categoryAll
        selectIndex(0, scroll: false)
    }
    
    public func moveSelection(up: Bool) {
        let count = filteredSnippets.count
        guard count > 0 else { return }
        let normalizedIndex = min(max(0, selectedIndex), count - 1)
        let nextIndex = up
            ? (normalizedIndex - 1 + count) % count
            : (normalizedIndex + 1) % count
        selectIndex(nextIndex, scroll: true)
    }
    
    public func selectIndex(_ index: Int, scroll: Bool) {
        let count = filteredSnippets.count
        guard count > 0 else {
            selectedIndex = 0
            shouldScroll = false
            return
        }
        selectedIndex = min(max(0, index), count - 1)
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
