import SwiftUI

struct ScreenCleaningOverlayView: View {
    @Bindable var appState: AppState
    let showInstructions: Bool
    
    @State private var progress: Double = 0
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if showInstructions {
                VStack(spacing: 20) {
                    Text(I18n.localized("screen_cleaning_active", language: appState.language))
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                    
                    Text(I18n.localized("screen_cleaning_exit_hint", language: appState.language))
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.4))
                    
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.1), lineWidth: 4)
                            .frame(width: 60, height: 60)
                        
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(Color.white.opacity(0.6), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .frame(width: 60, height: 60)
                            .rotationEffect(.degrees(-90))
                    }
                    .padding(.top, 20)
                    .opacity(progress > 0 ? 1 : 0)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .screenCleaningProgress)) { notification in
            if let value = notification.object as? Double {
                withAnimation(.linear(duration: 0.1)) {
                    progress = value
                }
            }
        }
    }
}
