import XCTest
import SwiftUI
@testable import MeowOut

@MainActor
final class CategoryDropDelegateTests: XCTestCase {
    
    func testDelegateInitialization() {
        let store = SnippetStore.shared
        @State var draggedItem: Snippet? = Snippet(title: "Title", content: "Content", category: "Test")
        @State var targetedCategory: String? = nil
        let binding = Binding(get: { draggedItem }, set: { draggedItem = $0 })
        let targetedBinding = Binding(get: { targetedCategory }, set: { targetedCategory = $0 })
        
        let delegate = CategoryDropDelegate(targetCategory: "NewCategory", draggedItem: binding, targetedCategory: targetedBinding, store: store)
        
        XCTAssertEqual(delegate.targetCategory, "NewCategory")
        XCTAssertEqual(delegate.draggedItem?.title, "Title")
    }
}
