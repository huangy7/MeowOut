import SwiftUI

struct AttachmentsLibraryView: View {
    @Environment(AppState.self) private var appState
    enum AttachmentTab: String, CaseIterable, Identifiable {
        case media = "Media"
        case audio = "Audio"
        case documents = "Documents"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .media:
                "photo"
            case .audio:
                "waveform"
            case .documents:
                "doc"
            }
        }
    }

    @State private var selectedTab: AttachmentTab = .media

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 12) {
                Text(I18n.localized("memos_category_attachments", language: appState.language))
                    .font(.system(size: 28, weight: .bold))

                Picker("", selection: $selectedTab) {
                    ForEach(AttachmentTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 360)
                .accessibilityLabel("附件类型")

                Spacer()

                Button {
                    NotificationCenter.default.post(name: .memosDidChange, object: nil)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("刷新")
                .accessibilityLabel("刷新附件")
            }

            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6]))
                .foregroundStyle(.tertiary)
                .overlay {
                    VStack(spacing: 12) {
                        Image(systemName: selectedTab.systemImage)
                            .font(.system(size: 44))
                            .foregroundStyle(.secondary)

                        Text(selectedTab.rawValue)
                            .font(.headline)

                        Text("暂无附件")
                            .foregroundStyle(.secondary)
                    }
                }
        }
        .padding(28)
    }
}
