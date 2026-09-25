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

/// 侧栏行的图标方块：彩色圆角底 + 白色符号，选中时换成半透明白底以适配高亮背景。
struct SidebarItemIcon: View {
    let item: SidebarItem
    let isSelected: Bool

    var body: some View {
        Image(systemName: item.icon)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(isSelected ? Color.white.opacity(0.25) : item.iconColor)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
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

/// 原生 List 版侧栏。选中态、悬停反馈、键盘上下键导航与 scroll-edge 效果都由系统绘制，
/// 外观与系统设置一致；配合 NavigationSplitView 使用时，工具栏项会自动对齐到分栏分隔线。
struct SidebarList: View {
    let sections: [SidebarSection]
    @Binding var selection: String?

    var body: some View {
        List(selection: $selection) {
            ForEach(sections) { section in
                if let title = section.title {
                    Section {
                        rows(for: section)
                    } header: {
                        Text(title)
                    }
                } else {
                    Section {
                        rows(for: section)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 148, ideal: 156, max: 176)
    }

    @ViewBuilder
    private func rows(for section: SidebarSection) -> some View {
        ForEach(section.items) { item in
            SidebarListRow(item: item, isSelected: selection == item.id)
                .tag(item.id)
        }
    }
}

/// List 侧栏的一行。选中背景由 List 绘制，这里只负责行内容本身。
private struct SidebarListRow: View {
    let item: SidebarItem
    let isSelected: Bool

    var body: some View {
        Label {
            HStack(spacing: 4) {
                Text(item.title)
                    .lineLimit(1)
                if item.hasBadge {
                    UpdateBadge()
                }
            }
        } icon: {
            SidebarItemIcon(item: item, isSelected: isSelected)
        }
        .accessibilityLabel(item.hasBadge
                            ? "\(item.title), \(I18n.localized("settings_update_badge_a11y"))"
                            : item.title)
    }
}
