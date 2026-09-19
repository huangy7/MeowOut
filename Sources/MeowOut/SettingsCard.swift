import SwiftUI

struct SettingsCard<Content: View, Trailing: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String?
    let tip: String?
    let isOn: Binding<Bool>?
    @ViewBuilder var content: () -> Content
    @ViewBuilder var trailing: () -> Trailing

    @State private var showTipPopover = false

    init(icon: String, iconColor: Color, title: String, description: String? = nil, tip: String? = nil, isOn: Binding<Bool>? = nil, @ViewBuilder content: @escaping () -> Content, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.description = description
        self.tip = tip
        self.isOn = isOn
        self.content = content
        self.trailing = trailing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                // Icon Box
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(iconColor.opacity(0.1))
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .foregroundStyle(iconColor)
                        .font(.system(size: 14, weight: .semibold))
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))

                        if let tip = tip {
                            Button(action: { showTipPopover.toggle() }) {
                                Image(systemName: "info.circle")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 12))
                            }
                            .buttonStyle(.plain)
                            .popover(isPresented: $showTipPopover, arrowEdge: .bottom) {
                                Text(tip)
                                    .font(.system(size: 12))
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(12)
                                    .frame(maxWidth: 220)
                            }
                        }
                    }
                    if let description = description {
                        Text(description)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)

                trailing()

                if let isOn = isOn {
                    Toggle(isOn: isOn) { EmptyView() }
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .accessibilityLabel(title)
                }
            }

            content()
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }
}

/// 仅下方内容(无右侧控件)
extension SettingsCard where Trailing == EmptyView {
    init(icon: String, iconColor: Color, title: String, description: String? = nil, tip: String? = nil, isOn: Binding<Bool>? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.init(icon: icon, iconColor: iconColor, title: title, description: description, tip: tip, isOn: isOn, content: content, trailing: { EmptyView() })
    }
}

/// 纯标题行卡片(如开关卡片)
extension SettingsCard where Content == EmptyView, Trailing == EmptyView {
    init(icon: String, iconColor: Color, title: String, description: String? = nil, tip: String? = nil, isOn: Binding<Bool>? = nil) {
        self.init(icon: icon, iconColor: iconColor, title: title, description: description, tip: tip, isOn: isOn, content: { EmptyView() }, trailing: { EmptyView() })
    }
}
