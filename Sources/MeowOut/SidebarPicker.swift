import SwiftUI

/// A sidebar tab item
struct SidebarItem: Identifiable, Hashable {
    let id: String
    let title: String
    let icon: String
    var iconColor: Color = .accentColor
    var hasBadge: Bool = false
}

/// A group of sidebar items with an optional section title
struct SidebarSection: Identifiable {
    let id: String
    let title: String?
    let items: [SidebarItem]

    init(id: String, title: String? = nil, items: [SidebarItem]) {
        self.id = id
        self.title = title
        self.items = items
    }
}

/// A macOS-style vertical sidebar tab bar.
/// Pair with HStack to create a full sidebar layout.
struct SidebarTabBar: View {
    let sections: [SidebarSection]
    @Binding var selection: String

    init(items: [SidebarItem], selection: Binding<String>) {
        self.sections = [SidebarSection(id: "main", items: items)]
        self._selection = selection
    }

    init(sections: [SidebarSection], selection: Binding<String>) {
        self.sections = sections
        self._selection = selection
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(sections) { section in
                    if let title = section.title {
                        Text(title)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.top, 12)
                            .padding(.bottom, 4)
                    }
                    ForEach(section.items) { item in
                        SidebarRowButton(item: item, isSelected: selection == item.id) {
                            selection = item.id
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 148, idealWidth: 156, maxWidth: 176)
        .background(VisualEffectView())
    }
}

private struct SidebarRowButton: View {
    let item: SidebarItem
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: item.icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(isSelected ? Color.white.opacity(0.25) : item.iconColor)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                Text(item.title)
                    .lineLimit(1)
                if item.hasBadge {
                    UpdateBadge()
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected
                      ? Color.accentColor
                      : (isHovered ? Color.primary.opacity(0.05) : .clear))
        )
        .foregroundStyle(isSelected ? Color.white : .primary)
        .onHover { isHovered = $0 }
        .accessibilityLabel(item.hasBadge
                            ? "\(item.title), \(I18n.localized("settings_update_badge_a11y"))"
                            : item.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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

struct VisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = .sidebar
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
