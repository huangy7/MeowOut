import SwiftUI
import KeyboardShortcuts
import MemosKit

struct MemosSettingsView: View {
    @Environment(AppState.self) private var appState
    @Bindable var state: AppState
    @State private var serverURL: String = ""
    @State private var patToken: String = ""
    @State private var showPAT = false
    @State private var connectionStatus: ConnectionStatus = .idle
    @State private var connectedUser: String = ""
    @State private var connectedVersion: String = ""
    @State private var pendingCount: Int = 0
    @State private var isSyncing = false
    private let pendingCountTimer = Timer.publish(every: 2.5, on: .main, in: .common).autoconnect()

    enum ConnectionStatus {
        case idle, testing, success, failure(String)
    }

    var body: some View {
        VStack(spacing: 16) {
            serverConnectionCard
            shortcutCard
            entryCard
            syncStatusCard
        }
        .onAppear {
            serverURL = MemosAuth.shared.baseURL?.absoluteString ?? ""
            patToken = MemosAuth.shared.pat ?? ""
            refreshPendingCount()
        }
        .onReceive(NotificationCenter.default.publisher(for: .memosDidChange)) { _ in
            refreshPendingCount()
        }
        .onReceive(pendingCountTimer) { _ in
            refreshPendingCount()
        }
    }

    @ViewBuilder
    private var serverConnectionCard: some View {
        SettingsCard(icon: "server.rack", iconColor: .blue, title: I18n.localized("memos_settings_server", language: appState.language), description: nil) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(I18n.localized("memos_settings_server_address", language: appState.language))
                        .frame(width: 80, alignment: .leading)
                    TextField("https://memos.example.com", text: $serverURL)
                        .textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("PAT Token")
                        .frame(width: 80, alignment: .leading)
                    if showPAT {
                        TextField("memos_pat_...", text: $patToken)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("memos_pat_...", text: $patToken)
                            .textFieldStyle(.roundedBorder)
                    }
                    Button(action: { showPAT.toggle() }) {
                        Image(systemName: showPAT ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.plain)
                }
                HStack {
                    Button(I18n.localized("memos_settings_test_connection", language: appState.language)) { testConnection() }
                        .disabled(serverURL.isEmpty || patToken.isEmpty)
                    statusView
                }
            }
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch connectionStatus {
        case .idle: EmptyView()
        case .testing: ProgressView().controlSize(.small)
        case .success:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("已连接 · Memos \(connectedVersion) · \(connectedUser)")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        case .failure(let msg):
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                Text(msg).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var shortcutCard: some View {
        SettingsCard(icon: "command", iconColor: .orange, title: I18n.localized("memos_settings_shortcuts", language: appState.language), description: nil) {
            VStack(spacing: 12) {
                HStack {
                    Text(I18n.localized("memos_settings_quick_capture", language: appState.language))
                    Spacer()
                    KeyboardShortcuts.Recorder(for: .toggleMemosQuickCapture)
                }
                HStack {
                    Text(I18n.localized("memos_settings_open_browser", language: appState.language))
                    Spacer()
                    KeyboardShortcuts.Recorder(for: .toggleMemosBrowserWindow)
                }
            }
        }
    }

    @ViewBuilder
    private var entryCard: some View {
        SettingsCard(icon: "rectangle.on.rectangle", iconColor: .purple, title: I18n.localized("memos_settings_entry", language: appState.language), description: nil) {
            HStack(spacing: 12) {
                Button {
                    NotificationCenter.default.post(name: .showMemosBrowserWindow, object: nil)
                } label: {
                    Label(I18n.localized("memos_action_open_memos", language: appState.language), systemImage: "macwindow")
                }

                Button {
                    NotificationCenter.default.post(name: .toggleQuickMemoPanel, object: nil)
                } label: {
                    Label(I18n.localized("memos_settings_quick_capture_short", language: appState.language), systemImage: "square.and.pencil")
                }
            }
        }
    }

    @ViewBuilder
    private var syncStatusCard: some View {
        SettingsCard(icon: "arrow.triangle.2.circlepath", iconColor: .green, title: I18n.localized("memos_settings_sync_status", language: appState.language), description: nil) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(I18n.localizedFormat("memos_status_sync_indicator", language: appState.language, pendingCount))
                        .font(.system(size: 13, weight: .medium))
                    Text(pendingCount == 0 ? I18n.localized("memos_settings_sync_empty", language: appState.language) : I18n.localized("memos_settings_sync_hint", language: appState.language))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    syncNow()
                } label: {
                    if isSyncing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(I18n.localized("memos_action_sync_now", language: appState.language))
                    }
                }
                .disabled(pendingCount == 0 || isSyncing)
            }
        }
    }

    private func testConnection() {
        guard let url = URL(string: serverURL), !patToken.isEmpty else { return }
        connectionStatus = .testing
        Task {
            do {
                try MemosAuth.shared.configure(baseURL: url, pat: patToken)
                let profile = try await MemosClient.shared.verifyConnection()
                let user = try await MemosClient.shared.getCurrentUser()
                connectedVersion = profile.version
                connectedUser = user.displayName.isEmpty ? user.username : user.displayName
                connectionStatus = .success
            } catch {
                connectionStatus = .failure(error.localizedDescription)
            }
        }
    }

    private func syncNow() {
        guard pendingCount > 0 else { return }
        isSyncing = true
        Task {
            await QueueProcessor.shared.processNow()
            refreshPendingCount()
            isSyncing = false
            NotificationCenter.default.post(name: .memosDidChange, object: nil)
        }
    }

    private func refreshPendingCount() {
        let currentPendingCount = OfflineQueue.shared.pendingCount
        guard pendingCount != currentPendingCount else { return }
        pendingCount = currentPendingCount
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                                  proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), positions)
    }
}
