import SwiftUI

/// Memos 窗口的画布底色，各栏统一取用。
///
/// 必须用 controlBackgroundColor，不能用 windowBackgroundColor：后者是动态色，在 macOS 27 SDK 下
/// 解析为白、在 macOS 15 SDK 下解析为约 236 的灰。CI 用 Xcode 16.4（SDK 15.x）出包，一旦用它，
/// 窗口整体会变灰，导航栏那层白底也会跟着显得像一条被截断的窄条。
/// controlBackgroundColor 在两个 SDK 下都是白，因此本地构建与发布包渲染一致。
enum MemosTheme {
    static let canvas = Color(NSColor.controlBackgroundColor)
}

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
        ZStack {
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
            .background(MemosTheme.canvas)

            if let activeURL = appState.activeImageURL {
                MemoImagePreviewOverlay(url: activeURL)
                    .transition(.opacity)
            }
        }
    }
}
