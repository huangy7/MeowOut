import SwiftUI

struct PillTabBar: View {
    let items: [String]
    @Binding var selection: String
    @Namespace private var animation

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items, id: \.self) { item in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selection = item
                    }
                } label: {
                    Text(item)
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                        .background {
                            if selection == item {
                                Capsule()
                                    .fill(Color.white)
                                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                                    .matchedGeometryEffect(id: "pill", in: animation)
                            }
                        }
                        .foregroundStyle(selection == item ? .primary : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.primary.opacity(0.05))
        .clipShape(Capsule())
    }
}
