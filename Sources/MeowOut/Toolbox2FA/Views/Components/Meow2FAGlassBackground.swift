import SwiftUI

public struct Meow2FAGlassBackground<Content: View>: View {
    @ViewBuilder let content: Content
    
    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    public var body: some View {
        ZStack {
            // Glowing Orbs
            GeometryReader { proxy in
                Circle()
                    .fill(Color.blue.opacity(0.3))
                    .blur(radius: 60)
                    .frame(width: proxy.size.width * 0.8)
                    .offset(x: -proxy.size.width * 0.2, y: -proxy.size.height * 0.2)
                
                Circle()
                    .fill(Color.pink.opacity(0.2))
                    .blur(radius: 60)
                    .frame(width: proxy.size.width * 0.8)
                    .offset(x: proxy.size.width * 0.4, y: proxy.size.height * 0.4)
            }
            .ignoresSafeArea()
            
            // Glass Material
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            
            // Content
            content
            
        }
    }
}

#Preview {
    Meow2FAGlassBackground {
        Text("Glass Content")
            .font(.largeTitle)
    }
    .frame(width: 400, height: 300)
}
