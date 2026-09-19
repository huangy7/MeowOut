import SwiftUI

/// 子标签项:以稳定的 id 作为选中标识,title 仅用于展示
struct PillTabItem: Identifiable, Hashable {
    let id: String
    let title: String
}

struct PillTabBar: View {
    let items: [PillTabItem]
    var badgeItems: Set<String> = []
    @Binding var selection: String
    @Namespace private var animation

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items) { item in
                let isSelected = selection == item.id
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selection = item.id
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(item.title)
                        if badgeItems.contains(item.id) {
                            UpdateBadge()
                        }
                    }
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                    .background {
                        if isSelected {
                            Capsule()
                                .fill(Color(nsColor: .controlBackgroundColor))
                                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                                .matchedGeometryEffect(id: "pill", in: animation)
                        }
                    }
                    .foregroundStyle(isSelected ? .primary : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Color.primary.opacity(0.05))
        .clipShape(Capsule())
    }
}
