import SwiftUI

struct ProgressRingView: View {
    var progress: Double // 0.0 to 1.0
    var timeRemaining: Int
    var warningThreshold: Int = 5
    
    var body: some View {
        let clampedProgress = min(max(progress, 0.0), 1.0)
        ZStack {
            Circle()
                .stroke(lineWidth: 3)
                .opacity(0.3)
                .foregroundColor(.gray)
            
            Circle()
                .trim(from: 0.0, to: CGFloat(clampedProgress))
                .stroke(style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .foregroundColor(timeRemaining <= warningThreshold ? .red : .blue)
                .rotationEffect(Angle(degrees: 270.0))
                .animation(.linear, value: progress)
        }
        .frame(width: 24, height: 24)
    }
}

#Preview {
    VStack(spacing: 20) {
        ProgressRingView(progress: 1.0, timeRemaining: 30)
        ProgressRingView(progress: 0.5, timeRemaining: 15)
        ProgressRingView(progress: 0.1, timeRemaining: 3)
    }
    .padding()
}
