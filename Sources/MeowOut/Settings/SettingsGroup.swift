import SwiftUI

/// 系统设置风格的分组卡片：小号灰色组标题 + 圆角卡片容器。
/// 卡片内自上而下放置 SettingsRow / SettingsRowDivider / 自定义内容。
struct SettingsGroup<Content: View>: View {
    let title: String?
    @ViewBuilder var content: () -> Content

    init(_ title: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 12)
            }
            VStack(spacing: 0) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
    }
}

/// 分组内的一行：左侧标题（+可选描述），右侧控件。
struct SettingsRow<Trailing: View>: View {
    let title: String
    let description: String?
    @ViewBuilder var trailing: () -> Trailing

    init(_ title: String, description: String? = nil, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.description = description
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                if let description {
                    Text(description)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}

/// 无右侧控件的行（纯展示或整宽内容）
extension SettingsRow where Trailing == EmptyView {
    init(_ title: String, description: String? = nil) {
        self.init(title, description: description, trailing: { EmptyView() })
    }
}

/// 行间发丝分隔线（左侧内缩与文字对齐）
struct SettingsRowDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 12)
    }
}
