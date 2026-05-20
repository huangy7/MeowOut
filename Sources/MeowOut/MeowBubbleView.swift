import SwiftUI

private struct BubbleSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        guard next != .zero else { return }
        value = next
    }
}

/// 专门用于气泡窗口的视图
public struct MeowBubbleView: View {
    @Bindable var petState: PetState
    var appState: AppState?
    var onWaterAdd: (() -> Void)?
    var onUpdateNow: (() -> Void)?
    var onUpdateLater: (() -> Void)?
    var onSizeChange: ((CGSize) -> Void)?
    @Environment(\.openWindow) private var openWindow

    public init(
        petState: PetState,
        appState: AppState? = nil,
        onWaterAdd: (() -> Void)? = nil,
        onUpdateNow: (() -> Void)? = nil,
        onUpdateLater: (() -> Void)? = nil,
        onSizeChange: ((CGSize) -> Void)? = nil
    ) {
        self.petState = petState
        self.appState = appState
        self.onWaterAdd = onWaterAdd
        self.onUpdateNow = onUpdateNow
        self.onUpdateLater = onUpdateLater
        self.onSizeChange = onSizeChange
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            if petState.bubbleVisible && !petState.bubbleText.isEmpty {
                VStack(spacing: 8) {
                    Text(petState.bubbleText)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    if petState.showBreathingButton {
                        Button(action: {
                            NSApp.activate(ignoringOtherApps: true)
                            openWindow(id: "breathing")
                        }) {
                            Text("🧘 正念练习")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.8))
                        .cornerRadius(10)
                    }

                    if petState.showWaterButton {
                        Button(action: {
                            onWaterAdd?()
                        }) {
                            Text("+1 杯")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.8))
                        .cornerRadius(10)
                    }

                    if petState.updateInteraction != nil {
                        HStack(spacing: 8) {
                            Button(action: {
                                petState.dismissUpdateBubble()
                                onUpdateNow?()
                            }) {
                                Text(I18n.localized("update_pet_action_open", language: appState?.language ?? .system))
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.red.opacity(0.85))
                            .cornerRadius(10)

                            Button(action: {
                                petState.dismissUpdateBubble()
                                onUpdateLater?()
                            }) {
                                Text(I18n.localized("update_pet_action_later", language: appState?.language ?? .system))
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.9))
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.18))
                            .cornerRadius(10)
                        }
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
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: BubbleSizePreferenceKey.self,
                            value: proxy.size
                        )
                    }
                )
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                    .transition(.scale(scale: 0.5, anchor: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: 260, maxHeight: .infinity)
        .onPreferenceChange(BubbleSizePreferenceKey.self) { size in
            guard petState.bubbleVisible, !petState.bubbleText.isEmpty else { return }
            guard size.width > 0, size.height > 0 else { return }
            onSizeChange?(size)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: petState.bubbleVisible)
    }
}
