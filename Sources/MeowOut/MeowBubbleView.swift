import SwiftUI

/// 专门用于气泡窗口的视图
public struct MeowBubbleView: View {
    @Bindable var petState: PetState

    public init(petState: PetState) {
        self.petState = petState
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            if petState.bubbleVisible && !petState.bubbleText.isEmpty {
                Text(petState.bubbleText)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.85))
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color.orange.opacity(0.6), lineWidth: 1.5)
                    )
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                    .transition(.scale(scale: 0.5, anchor: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: petState.bubbleVisible)
    }
}
