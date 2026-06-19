import SwiftUI
import UniformTypeIdentifiers

struct SnippetDropDelegate: DropDelegate {
    let item: Snippet
    let items: [Snippet]
    @Binding var draggedItem: Snippet?
    let searchText: String
    let store: SnippetStore
    
    func dropEntered(info: DropInfo) {
        // Only allow reordering when not searching
        guard searchText.isEmpty else { return }
        
        guard let draggedItem = draggedItem,
              draggedItem.id != item.id,
              let from = items.firstIndex(where: { $0.id == draggedItem.id }),
              let to = items.firstIndex(where: { $0.id == item.id }) else { return }
        
        if from != to {
            withAnimation(.default) {
                store.moveSnippet(id: draggedItem.id, toOffset: to > from ? to + 1 : to, inFilteredList: items)
            }
        }
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: searchText.isEmpty ? .move : .forbidden)
    }
    
    func performDrop(info: DropInfo) -> Bool {
        draggedItem = nil
        return true
    }
}
