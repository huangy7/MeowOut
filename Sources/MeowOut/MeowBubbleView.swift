import SwiftUI

/// 专门用于气泡窗口的视图
public struct MeowBubbleView: View {
    @Bindable var petState: PetState
    @Environment(\.openWindow) private var openWindow

    public init(petState: PetState) {
        self.petState = petState
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            if petState.bubbleVisible && !petState.bubbleText.isEmpty {
                VStack(spacing: 8) {
                    Text(petState.bubbleText)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        
                    if petState.showBreathingButton {
                        Button(action: {
                            NSApp.activate(ignoringOtherApps: true)
                            openWindow(id: "breathing")
                        }) {
                            Text("🧘 深呼吸")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.8))
                        .cornerRadius(10)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.black.opacity(0.85))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
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
