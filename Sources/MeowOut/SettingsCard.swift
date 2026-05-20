import SwiftUI

struct SettingsCard<Content: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String?
    @ViewBuilder var content: () -> Content

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
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                    if let description = description {
                        Text(description)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            content()
        }
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }
}
