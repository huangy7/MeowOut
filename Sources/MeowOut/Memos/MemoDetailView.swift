import AppKit
import SwiftUI
import MemosKit
import MarkdownUI

struct MemoDetailView: View {
    @Binding var memo: Memo?
    let mode: MemosCollectionMode

    @State private var isEditing = false
    @State private var editText = ""
    @State private var errorMessage: String?
    @State private var showingDeleteAlert = false
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            if let memo {
                if isEditing {
                    editingView
                } else {
                    readingView(memo)
                }
            } else {
                ContentUnavailableView(I18n.localized("memos_placeholder_select_memo", language: appState.language), systemImage: "note.text")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            editText = memo?.content ?? ""
        }
        .onChange(of: memo?.name) { _, _ in
            isEditing = false
            editText = memo?.content ?? ""
            errorMessage = nil
        }
        .alert(I18n.localized("memo_delete_confirm_title", language: appState.language), isPresented: $showingDeleteAlert) {
            Button(I18n.localized("memo_delete_confirm_cancel", language: appState.language), role: .cancel) { }
            Button(I18n.localized("memo_delete_confirm_delete", language: appState.language), role: .destructive) { performDelete() }
        } message: {
            Text(I18n.localized("memo_delete_confirm_message", language: appState.language))
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            if let memo {
                VStack(alignment: .leading, spacing: 2) {
                    Text(memo.createTime, format: .dateTime.year().month().day().hour().minute())
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 12))
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if isEditing && mode.allowsEditing {
                    Button(I18n.localized("memos_action_cancel", language: appState.language)) {
                        cancelEdit()
                    }
                    .keyboardShortcut(.cancelAction)

                    Button("完成") {
                        saveEdit()
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                } else {
                    if mode.allowsEditing {
                        Button(I18n.localized("memos_action_edit", language: appState.language)) {
                            beginEditing()
                        }
                    }

                    if mode.allowsArchiving {
                        Button(I18n.localized("memos_action_archive", language: appState.language)) {
                            archive()
                        }
                    }

                    if mode.allowsRestoring {
                        Button(I18n.localized("memos_action_restore", language: appState.language)) {
                            restore()
                        }
                    }

                    Menu {
                        if mode.allowsEditing {
                            Button(memo.pinned ? I18n.localized("memos_action_unpin", language: appState.language) : I18n.localized("memos_action_pin", language: appState.language)) { togglePin() }
                            Button(I18n.localized("memos_action_edit", language: appState.language)) { beginEditing() }
                        }
                        Button(I18n.localized("memos_action_copy", language: appState.language)) { copyContent() }
                        if mode.allowsArchiving {
                            Button(I18n.localized("memos_action_archive", language: appState.language)) { archive() }
                        }
                        if mode.allowsRestoring {
                            Button(I18n.localized("memos_action_restore", language: appState.language)) { restore() }
                        }
                        Divider()
                        Button(I18n.localized("memos_action_delete", language: appState.language), role: .destructive) { delete() }
                    } label: {
                        Label(I18n.localized("memos_action_more", language: appState.language), systemImage: "ellipsis.circle")
                            .labelStyle(.iconOnly)
                    }
                    .menuStyle(.borderlessButton)
                    .help(I18n.localized("memos_action_more", language: appState.language))
                }
            } else {
                Spacer()
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 72)
    }

    private var editingView: some View {
        VStack(spacing: 0) {
            TextEditor(text: $editText)
                .font(.system(size: 17))
                .lineSpacing(5)
                .scrollContentBackground(.hidden)
                .padding(28)
        }
    }

    private func readingView(_ memo: Memo) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Markdown(memo.content)
                    .markdownTheme(.gitHub)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !memo.tags.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(memo.tags, id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(.quaternary, in: Capsule())
                        }
                    }
                }
            }
            .padding(42)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func beginEditing() {
        guard mode.allowsEditing else { return }
        editText = memo?.content ?? ""
        isEditing = true
        errorMessage = nil
    }

    private func cancelEdit() {
        editText = memo?.content ?? ""
        isEditing = false
        errorMessage = nil
    }

    private func saveEdit() {
        guard mode.allowsEditing else { return }
        guard var currentMemo = memo else { return }
        let targetName = currentMemo.name
        let content = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else {
            errorMessage = "内容不能为空"
            return
        }

        isEditing = false
        errorMessage = nil

        Task {
            do {
                let updated = try await MemosClient.shared.updateMemo(
                    name: targetName,
                    content: content,
                    updateMask: ["content"]
                )
                await MainActor.run {
                    guard isCurrentMemo(targetName) else { return }
                    memo = updated
                    NotificationCenter.default.post(name: .memosDidChange, object: nil)
                }
            } catch {
                let shouldEnqueue = shouldEnqueueMutation(after: error)
                if shouldEnqueue {
                    QueueProcessor.shared.enqueueAndProcess(.update(
                        memoName: targetName,
                        content: content,
                        state: nil,
                        updateMask: ["content"]
                    ))
                }

                await MainActor.run {
                    guard isCurrentMemo(targetName) else { return }
                    if shouldEnqueue {
                        currentMemo.content = content
                        memo = currentMemo
                        errorMessage = I18n.localized("memos_status_staged_sync", language: appState.language)
                        NotificationCenter.default.post(name: .memosDidChange, object: nil)
                    } else {
                        isEditing = true
                        errorMessage = mutationFailureMessage(for: error, action: I18n.localized("memos_action_save", language: appState.language))
                    }
                }
            }
        }
    }

    private func archive() {
        guard mode.allowsArchiving else { return }
        guard let currentMemo = memo else { return }
        let targetName = currentMemo.name
        errorMessage = nil

        Task {
            do {
                _ = try await MemosClient.shared.updateMemo(
                    name: targetName,
                    state: .archived,
                    updateMask: ["state"]
                )
                await MainActor.run {
                    guard isCurrentMemo(targetName) else { return }
                    memo = nil
                    NotificationCenter.default.post(name: .memosDidChange, object: nil)
                }
            } catch {
                let shouldEnqueue = shouldEnqueueMutation(after: error)
                if shouldEnqueue {
                    QueueProcessor.shared.enqueueAndProcess(.update(
                        memoName: targetName,
                        content: nil,
                        state: .archived,
                        updateMask: ["state"]
                    ))
                }

                await MainActor.run {
                    guard isCurrentMemo(targetName) else { return }
                    if shouldEnqueue {
                        memo = nil
                        NotificationCenter.default.post(name: .memosDidChange, object: nil)
                    } else {
                        errorMessage = mutationFailureMessage(for: error, action: I18n.localized("memos_action_archive", language: appState.language))
                    }
                }
            }
        }
    }

    private func restore() {
        guard mode.allowsRestoring else { return }
        guard let currentMemo = memo else { return }
        let targetName = currentMemo.name
        errorMessage = nil

        Task {
            do {
                _ = try await MemosClient.shared.updateMemo(
                    name: targetName,
                    state: .normal,
                    updateMask: ["state"]
                )
                await MainActor.run {
                    guard isCurrentMemo(targetName) else { return }
                    memo = nil
                    NotificationCenter.default.post(name: .memosDidChange, object: nil)
                }
            } catch {
                let shouldEnqueue = shouldEnqueueMutation(after: error)
                if shouldEnqueue {
                    QueueProcessor.shared.enqueueAndProcess(.update(
                        memoName: targetName,
                        content: nil,
                        state: .normal,
                        updateMask: ["state"]
                    ))
                }

                await MainActor.run {
                    guard isCurrentMemo(targetName) else { return }
                    if shouldEnqueue {
                        memo = nil
                        NotificationCenter.default.post(name: .memosDidChange, object: nil)
                    } else {
                        errorMessage = mutationFailureMessage(for: error, action: I18n.localized("memos_action_restore", language: appState.language))
                    }
                }
            }
        }
    }

    private func togglePin() {
        guard let currentMemo = memo else { return }
        let targetName = currentMemo.name
        errorMessage = nil

        Task {
            do {
                let updated = try await MemosClient.shared.updateMemo(
                    name: targetName,
                    pinned: !currentMemo.pinned,
                    updateMask: ["pinned"]
                )
                await MainActor.run {
                    guard isCurrentMemo(targetName) else { return }
                    memo = updated
                    NotificationCenter.default.post(name: .memosDidChange, object: nil)
                }
            } catch {
                await MainActor.run {
                    guard isCurrentMemo(targetName) else { return }
                    errorMessage = mutationFailureMessage(for: error, action: I18n.localized("memos_action_pin", language: appState.language))
                }
            }
        }
    }

    private func copyContent() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(memo?.content ?? "", forType: .string)
    }

    private func delete() {
        showingDeleteAlert = true
    }

    private func performDelete() {
        guard let currentMemo = memo else { return }
        let targetName = currentMemo.name
        errorMessage = nil

        Task {
            do {
                try await MemosClient.shared.deleteMemo(name: targetName)
                await MainActor.run {
                    guard isCurrentMemo(targetName) else { return }
                    memo = nil
                    NotificationCenter.default.post(name: .memosDidChange, object: nil)
                }
            } catch {
                let shouldEnqueue = shouldEnqueueMutation(after: error)
                if shouldEnqueue {
                    QueueProcessor.shared.enqueueAndProcess(.delete(memoName: targetName))
                }

                await MainActor.run {
                    guard isCurrentMemo(targetName) else { return }
                    if shouldEnqueue {
                        memo = nil
                        NotificationCenter.default.post(name: .memosDidChange, object: nil)
                    } else {
                        errorMessage = mutationFailureMessage(for: error, action: I18n.localized("memos_action_delete", language: appState.language))
                    }
                }
            }
        }
    }

    private func isCurrentMemo(_ targetName: String) -> Bool {
        memo?.name == targetName
    }

    private func shouldEnqueueMutation(after error: Error) -> Bool {
        guard let memosError = error as? MemosError else {
            return false
        }

        switch memosError {
        case .networkError:
            return true
        case .serverError(let statusCode, _):
            return (500..<600).contains(statusCode)
        case .notConfigured, .unauthorized, .decodingError:
            return false
        }
    }

    private func mutationFailureMessage(for error: Error, action: String) -> String {
        guard let memosError = error as? MemosError else {
            return "\(action)失败，请稍后重试"
        }

        switch memosError {
        case .notConfigured:
            return "\(action)失败，请先配置 Memos"
        case .unauthorized:
            return "\(action)失败，请检查 Memos 凭证"
        case .decodingError:
            return "\(action)失败，服务器响应无法解析"
        case .serverError(let statusCode, _):
            if (400..<500).contains(statusCode) {
                return "\(action)失败，请检查权限或内容"
            }
            return "\(action)失败，请稍后重试"
        case .networkError:
            return "\(action)失败，请检查网络"
        }
    }
}
