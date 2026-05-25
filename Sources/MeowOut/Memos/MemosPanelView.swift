import SwiftUI
import MemosKit

struct MemosPanelView: View {
    @Environment(AppState.self) private var appState
    @State private var inputText = ""
    @State private var selectedTags: Set<String> = []
    @State private var sendStatus: SendStatus = .idle

    enum SendStatus: Equatable {
        case idle, sending, success, queued, failed(String)
    }

    private var isConfigured: Bool { MemosClient.shared.isConfigured }

    var body: some View {
        VStack(spacing: 0) {
            if isConfigured {
                configuredContent
            } else {
                onboardingContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onExitCommand { handleEsc() }
    }

    @ViewBuilder
    private var configuredContent: some View {
        MemoInputView(
            inputText: $inputText,
            selectedTags: $selectedTags,
            availableTags: combinedTags,
            pendingCount: OfflineQueue.shared.pendingCount,
            isConfigured: true,
            onSend: sendMemo
        )

        if case .success = sendStatus {
            HStack {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text(I18n.localized("memos_status_sent", language: appState.language)).font(.system(size: 11)).foregroundStyle(.green)
            }
            .transition(.opacity)
            .padding(.horizontal, 12)
        } else if case .queued = sendStatus {
            HStack {
                Image(systemName: "clock").foregroundStyle(.orange)
                Text(I18n.localized("memos_status_staged", language: appState.language)).font(.system(size: 11)).foregroundStyle(.orange)
            }
            .padding(.horizontal, 12)
        }

        Divider()

        MemoTimelineView(allTags: combinedTags)
    }

    @ViewBuilder
    private var onboardingContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "note.text")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(I18n.localized("memos_settings_connect_prompt", language: appState.language))
                .font(.system(size: 14, weight: .medium))
            Text(I18n.localized("memos_settings_connect_desc", language: appState.language))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(I18n.localized("memos_action_open_settings", language: appState.language)) {
                appState.settingsNavigationTarget = .memos
                NotificationCenter.default.post(name: NSNotification.Name("OpenSettingsWindow"), object: nil)
                MemosPanelController.shared.hide()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private var combinedTags: [String] {
        var tags = appState.memosDefaultTags
        for t in appState.memosTagHistory where !tags.contains(t) {
            tags.append(t)
        }
        return tags
    }

    private func sendMemo() {
        let content = buildContent()
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let visibility = MemoVisibility(rawValue: appState.memosDefaultVisibility) ?? .private

        sendStatus = .sending
        Task {
            do {
                _ = try await MemosClient.shared.createMemo(content: content, visibility: visibility)
                sendStatus = .success
                inputText = ""
                selectedTags = []
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                sendStatus = .idle
            } catch {
                QueueProcessor.shared.enqueueAndProcess(
                    .create(content: content, visibility: visibility, archiveAfterCreate: false))
                sendStatus = .queued
                inputText = ""
                selectedTags = []
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                sendStatus = .idle
            }
        }
    }

    private func buildContent() -> String {
        var text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        for tag in selectedTags {
            if !text.contains("#\(tag)") {
                text += " #\(tag)"
            }
        }
        return text
    }

    private func handleEsc() {
        if !inputText.isEmpty {
            inputText = ""
            selectedTags = []
        } else {
            MemosPanelController.shared.hide()
        }
    }
}
