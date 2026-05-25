import SwiftUI

enum MemosRootPage: String, CaseIterable, Identifiable {
    case memos
    case archived
    case attachments

    var id: String { rawValue }

    var title: String {
        switch self {
        case .memos:
            I18n.localized("memos_category_memos")
        case .archived:
            I18n.localized("memos_action_archive")
        case .attachments:
            I18n.localized("memos_category_attachments")
        }
    }

    var systemImage: String {
        switch self {
        case .memos:
            "note.text"
        case .archived:
            "archivebox"
        case .attachments:
            "paperclip"
        }
    }
}

struct MemosRootView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedPage: MemosRootPage = .memos

    var body: some View {
        HStack(spacing: 0) {
            MemosNavigationRail(selectedPage: $selectedPage)
                .frame(width: 72)

            Divider()

            Group {
                switch selectedPage {
                case .memos:
                    MemosHomeView(mode: .normal)
                case .archived:
                    MemosHomeView(mode: .archived)
                case .attachments:
                    AttachmentsLibraryView()
                }
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}
