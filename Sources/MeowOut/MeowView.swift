import SwiftUI

/// 专门用于猫猫主体的视图，保持窗口极小
public struct MeowView: View {
    @Bindable var appState: AppState
    @Bindable var petState: PetState

    var onDragStarted: () -> Void
    var onDragChanged: (CGSize) -> Void
    var onDragEnded: (CGSize) -> Void

    @State private var dragStarted = false

    public init(appState: AppState,
                petState: PetState,
                onDragStarted: @escaping () -> Void,
                onDragChanged: @escaping (CGSize) -> Void,
                onDragEnded: @escaping (CGSize) -> Void) {
        self.appState = appState
        self.petState = petState
        self.onDragStarted = onDragStarted
        self.onDragChanged = onDragChanged
        self.onDragEnded = onDragEnded
    }

    public var body: some View {
        ClawdView(pose: petState.pose, height: 40, isWalking: petState.isWalking, followMouse: true)
            .contentShape(Rectangle())
            .scaleEffect(x: (petState.facingRight ? 1 : -1) * (petState.isBeingDragged ? 1.1 : 1),
                         y: petState.isBeingDragged ? 1.1 : 1)
            .onTapGesture {
                handleTap()
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 5)
                    .onChanged { value in
                        if !dragStarted {
                            dragStarted = true
                            onDragStarted()
                        }
                        onDragChanged(value.translation)
                    }
                    .onEnded { value in
                        onDragEnded(value.translation)
                        dragStarted = false
                    }
            )
            .frame(width: 60, height: 60) // Tiny window footprint
    }

    private func handleTap() {
        let pack = DialogueManager.pack(for: appState.selectedPersonality, language: appState.language)
        if let quote = pack.tapQuotes.randomElement() {
            petState.showLockedBubble(quote)
        }
    }
}
