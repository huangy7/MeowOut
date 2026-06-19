import SwiftUI
import UniformTypeIdentifiers

struct CategoryDropDelegate: DropDelegate {
    let targetCategory: String
    @Binding var draggedItem: Snippet?
    @Binding var targetedCategory: String?
    let store: SnippetStore
    
    func dropEntered(info: DropInfo) {
        guard draggedItem != nil else { return }
        if targetCategory == KeyDropConstants.categoryAll { return }
        if let draggedItem = draggedItem, draggedItem.category == targetCategory { return }
        
        withAnimation(.easeInOut(duration: 0.2)) {
            targetedCategory = targetCategory
        }
    }
    
    func dropExited(info: DropInfo) {
        if targetedCategory == targetCategory {
            withAnimation(.easeInOut(duration: 0.2)) {
                targetedCategory = nil
            }
        }
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard draggedItem != nil else { return DropProposal(operation: .forbidden) }
        
        // Prevent dropping onto "全部"
        if targetCategory == KeyDropConstants.categoryAll {
            return DropProposal(operation: .forbidden)
        }
        // If snippet is already in this category, forbid drop
        if let draggedItem = draggedItem, draggedItem.category == targetCategory {
            return DropProposal(operation: .forbidden)
        }
        return DropProposal(operation: .move)
    }
    
    func performDrop(info: DropInfo) -> Bool {
        guard let draggedItem = draggedItem else { return false }
        if targetCategory == KeyDropConstants.categoryAll { return false }
        
        var updatedSnippet = draggedItem
        updatedSnippet.category = targetCategory
        withAnimation {
            store.update(snippet: updatedSnippet)
            self.targetedCategory = nil
        }
        self.draggedItem = nil
        return true
    }
}
