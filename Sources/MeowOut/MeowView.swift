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
        Group {
            appState.selectedPet.makeView(pose: petState.pose, height: 40, isWalking: petState.isWalking)
        }
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
        .frame(width: 60, height: 60)
        .contextMenu {
            Button("打开设置面板") {
                NSApp.activate(ignoringOtherApps: true)
                NotificationCenter.default.post(name: NSNotification.Name("OpenSettingsWindow"), object: nil)
            }
            
            Button("赶跑桌宠") {
                NotificationCenter.default.post(name: NSNotification.Name("TriggerEscapeHatch"), object: nil)
            }
        }
    }

    private func handleTap() {
        // If there's an update interaction active, prioritize it.
        // Tapping the cat while updating should show a special evolution-related quote
        // but keep the buttons visible.
        if petState.updateInteraction != nil {
            let pack = DialogueManager.pack(for: appState.selectedPersonality, language: appState.language)
            // Use a specific evolution quote if available, otherwise a generic tap quote
            let quote = pack.tapQuotes.randomElement() ?? ""
            petState.showLockedBubble(quote, duration: 2.0)
            
            // Re-lock after a short delay or just let it stay locked because updateInteraction is still there?
            // Actually, we need to ensure CatOverlayController doesn't overwrite this with idle chatter.
            // But showLockedBubble sets isBubbleLocked = true. After 2s it becomes false.
            // We want it to revert to the update prompt if the user hasn't acted.
            return
        }

        guard appState.currentState == .alerting || appState.currentState == .resting || appState.currentState == .overworking else {
            let pack = DialogueManager.pack(for: appState.selectedPersonality, language: appState.language)
            if let quote = pack.tapQuotes.randomElement() {
                petState.showLockedBubble(quote)
            }
            return
        }

        petState.tapCount += 1
        let targetCount = (appState.currentState == .alerting) ? 3 : 5
        let quote = DialogueManager.phasedEscapeQuotes(
            personality: appState.selectedPersonality,
            language: appState.language,
            current: petState.tapCount,
            target: targetCount
        )
        
        petState.showLockedBubble(quote, duration: 2.0)

        if petState.tapCount >= targetCount {
            petState.tapCount = 0
            NotificationCenter.default.post(name: NSNotification.Name("TriggerEscapeHatch"), object: nil)
        }
    }
}
