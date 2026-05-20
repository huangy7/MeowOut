import SwiftUI

/// A sidebar tab item
struct SidebarItem: Identifiable, Hashable {
    let id: String
    let title: String
    let icon: String
    var hasBadge: Bool = false
}

/// A macOS-style vertical sidebar tab bar.
/// Pair with HStack to create a full sidebar layout.
struct SidebarTabBar: View {
    let items: [SidebarItem]
    @Binding var selection: String

    var body: some View {
        VStack(spacing: 0) {
            ForEach(items) { item in
                sidebarButton(item)
            }
            Spacer()
        }
        .frame(width: 142)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.4))
    }

    private func sidebarButton(_ item: SidebarItem) -> some View {
        let isSelected = selection == item.id
        return Button {
            selection = item.id
        } label: {
            HStack(spacing: 8) {
                Image(systemName: item.icon)
                    .frame(width: 16)
                Text(item.title)
                if item.hasBadge {
                    UpdateBadge()
                }
            }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isSelected ? Color.accentColor.opacity(0.12) : .clear)
        .foregroundStyle(isSelected ? Color.accentColor : .primary)
    }
}

struct UpdateBadge: View {
    var body: some View {
        Circle()
            .fill(Color.red)
            .frame(width: 7, height: 7)
            .accessibilityHidden(true)
    }
}
