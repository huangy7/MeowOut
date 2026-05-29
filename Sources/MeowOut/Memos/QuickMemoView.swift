import SwiftUI
import MemosKit
import UniformTypeIdentifiers

struct QuickMemoView: View {
    @Environment(AppState.self) private var appState

    @FocusState private var isEditorFocused: Bool
    @State private var text: String = ""
    @State private var visibility: MemoVisibility = .private
    @State private var statusPresentation: QuickMemoStatusPresentation?
    @State private var isSaving = false
    @State private var suppressDraftPersistence = false
    @State private var createdAt = Date()
    @State private var uploadedAttachments: [Attachment] = []

    private let draftStore = QuickMemoDraftStore.shared
    @StateObject private var uploadManager = ImageUploadManager()

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmedText.isEmpty && !isSaving && !uploadManager.isUploading
    }

    private var memoTitle: String {
        QuickMemoTitleFormatter.title(for: text)
    }

    var body: some View {
        VStack(spacing: 0) {
            editor

            if !uploadedAttachments.isEmpty {
                EditorAttachmentListView(attachments: uploadedAttachments, onRemove: { attachment in
                    uploadedAttachments.removeAll { $0.name == attachment.name }
                })
                .padding(.bottom, 8)
            }

            if let statusPresentation {
                statusBanner(statusPresentation)
                .transition(.opacity)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDroppedFiles(providers)
        }
        .frame(minWidth: 400, minHeight: 360)
        .background(Color(nsColor: .textBackgroundColor))
        .onAppear {
            restoreDraft()
            updateWindowTitle()
        }
        .onChange(of: text) { _, _ in
            persistDraft()
            updateWindowTitle()
        }
        .onChange(of: visibility) { _, _ in
            persistDraft()
        }
        .onExitCommand {
            QuickMemoPanelController.shared.hide()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                formatMenu
            }

            ToolbarItem(placement: .primaryAction) {
                toolbarIcon("checklist", help: I18n.localized("memos_editor_insert_list", language: appState.language)) { insertMarkdown("- [ ] ") }
            }

            ToolbarItem(placement: .primaryAction) {
                toolbarIcon("tablecells", help: I18n.localized("memos_editor_insert_table", language: appState.language)) {
                    insertMarkdown("| 列 1 | 列 2 |\n| --- | --- |\n|  |  |")
                }
            }

            ToolbarItem(placement: .primaryAction) {
                toolbarIcon("paperclip", help: I18n.localized("memos_editor_insert_attachment", language: appState.language)) {
                    selectImageAndUpload()
                }
            }

            ToolbarItem(placement: .primaryAction) {
                moreMenu
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    save()
                } label: {
                    if isSaving || uploadManager.isUploading {
                        ProgressView().controlSize(.small).frame(width: 28)
                    } else {
                        Image(systemName: "paperplane")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(canSave ? .primary : .secondary)
                    }
                }
                .buttonStyle(.plain)
                .frame(width: 28, height: 28)
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(!canSave)
                .help(I18n.localized("memos_editor_save_and_send", language: appState.language))
            }
        }
    }

    private var formatMenu: some View {
        Menu {
            Button(I18n.localized("memos_editor_format_heading", language: appState.language)) { insertMarkdown("## ") }
            Button(I18n.localized("memos_editor_format_bold", language: appState.language)) { insertMarkdown("**文本**") }
            Button(I18n.localized("memos_editor_format_quote", language: appState.language)) { insertMarkdown("> ") }
        } label: {
            Text(I18n.localized("memos_editor_format_label", language: appState.language))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(height: 28)
        .help(I18n.localized("memos_editor_format_label", language: appState.language))
    }

    private var moreMenu: some View {
        Menu {
            Button {
                insertMarkdown("[链接](https://)")
            } label: {
                Label(I18n.localized("memos_editor_format_link", language: appState.language), systemImage: "link")
            }

            Button {
                pasteImageAndUpload()
            } label: {
                Label(I18n.localized("memos_action_paste_image", language: appState.language), systemImage: "doc.on.clipboard")
            }
            .keyboardShortcut("v", modifiers: [.command, .option])

            Menu {
                if appState.memosTagHistory.isEmpty {
                    Button("#标签") {
                        insertTag(I18n.localized("memos_editor_format_tag", language: appState.language))
                    }
                } else {
                    ForEach(appState.memosTagHistory.prefix(12), id: \.self) { tag in
                        Button("#\(tag)") {
                            insertTag(tag)
                        }
                    }
                }

                Divider()

                Button(I18n.localized("memos_editor_format_insert_tag", language: appState.language)) {
                    insertTag(I18n.localized("memos_editor_format_tag", language: appState.language))
                }
            } label: {
                Label(I18n.localized("memos_editor_format_tag", language: appState.language), systemImage: "number")
            }

            Picker(I18n.localized("memos_editor_visibility_label", language: appState.language), selection: $visibility) {
                Text(I18n.localized("memos_editor_visibility_private", language: appState.language)).tag(MemoVisibility.private)
                Text(I18n.localized("memos_editor_visibility_protected", language: appState.language)).tag(MemoVisibility.protected)
                Text(I18n.localized("memos_editor_visibility_public", language: appState.language)).tag(MemoVisibility.public)
            }

            Divider()

            Button {
                NotificationCenter.default.post(name: .showMemosBrowserWindow, object: nil)
                QuickMemoPanelController.shared.hide()
            } label: {
                Label(I18n.localized("memos_action_open_memos", language: appState.language), systemImage: "rectangle.stack")
            }

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            } label: {
                Label(I18n.localized("memos_action_copy_all", language: appState.language), systemImage: "doc.on.doc")
            }
            .disabled(text.isEmpty)

            Divider()

            Button(role: .destructive) {
                clearDraftAndEditor()
            } label: {
                Label(I18n.localized("memos_action_clear_draft", language: appState.language), systemImage: "trash")
            }
            .disabled(text.isEmpty)

            Button {
                QuickMemoPanelController.shared.hide()
            } label: {
                Label(I18n.localized("memos_action_close_window", language: appState.language), systemImage: "xmark")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .help(I18n.localized("memos_action_more", language: appState.language))
    }

    private func toolbarIcon(_ systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func statusBanner(_ presentation: QuickMemoStatusPresentation) -> some View {
        HStack(spacing: 10) {
            Image(systemName: presentation.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(presentation.isError ? .red : .green)

            Text(presentation.message)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(presentation.isError ? .red : .secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            if let actionTitle = presentation.actionTitle {
                Button(actionTitle) {
                    handleStatusAction(presentation)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 0)
                .fill(presentation.isError ? Color.red.opacity(0.10) : Color.green.opacity(0.10))
        )
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private var editor: some View {
        VStack(spacing: 0) {
            Text(createdAt, format: .dateTime.year().month().day().hour().minute())
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.tertiary)
                .padding(.top, 8)
                .padding(.bottom, 8)

            ZStack(alignment: .topLeading) {
                if text.isEmpty && !isEditorFocused {
                    Text(I18n.localized("memos_editor_placeholder_alt", language: appState.language))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 49)
                        .padding(.vertical, 12)
                }

                TextEditor(text: $text)
                    .font(.system(size: 17, weight: .semibold))
                    .lineSpacing(4)
                    .scrollContentBackground(.hidden)
                    .background(
                        TextEditorConfigurator { scrollView in
                            if let textView = scrollView.documentView as? NSTextView {
                                textView.textContainerInset = NSSize(width: 44, height: 12)
                            }
                        }
                    )
                    .focused($isEditorFocused)
                    .disabled(isSaving)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onAppear {
            isEditorFocused = true
        }
    }

    private func restoreDraft() {
        guard let draft = draftStore.load() else {
            visibility = .private
            return
        }

        text = draft.content
        visibility = MemoVisibility(rawValue: draft.visibility) ?? .private
    }

    private func persistDraft() {
        guard !suppressDraftPersistence else {
            return
        }

        draftStore.save(QuickMemoDraft(content: text, visibility: visibility.rawValue))
    }

    private func updateWindowTitle() {
        NotificationCenter.default.post(
            name: .quickMemoTitleDidChange,
            object: nil,
            userInfo: ["title": memoTitle]
        )
    }

    private func clearDraftAndEditor() {
        suppressDraftPersistence = true
        text = ""
        visibility = .private
        uploadedAttachments = []
        draftStore.clear()

        Task { @MainActor in
            await Task.yield()
            suppressDraftPersistence = false
        }
    }

    private func insertTag(_ rawTag: String) {
        let tag = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty else {
            return
        }

        insertMarkdown("#\(tag)")
    }

    private func insertMarkdown(_ markdown: String) {
        let insertion = markdown.trimmingCharacters(in: .newlines)

        if text.isEmpty || text.hasSuffix(" ") || text.hasSuffix("\n") {
            text += insertion
        } else if insertion.hasPrefix("#") {
            text += " \(insertion)"
        } else {
            text += "\n\n\(insertion)"
        }

        isEditorFocused = true
    }

    private func save() {
        let content = trimmedText
        guard !content.isEmpty, !isSaving else {
            return
        }
        let submittedVisibility = visibility

        isSaving = true
        statusPresentation = nil

        let finalAttachments = uploadedAttachments

        Task {
            do {
                _ = try await MemosClient.shared.createMemo(content: content, visibility: submittedVisibility, attachments: finalAttachments)
                NotificationCenter.default.post(name: .memosDidChange, object: nil)

                await MainActor.run {
                    clearDraftAndEditor()
                    statusPresentation = nil
                    isSaving = false
                    QuickMemoPanelController.shared.hide()
                }
            } catch {
                let shouldEnqueue = shouldEnqueueCreate(after: error)

                if shouldEnqueue {
                    QueueProcessor.shared.enqueueAndProcess(
                        .create(content: content, visibility: submittedVisibility, attachments: finalAttachments, archiveAfterCreate: false)
                    )
                    NotificationCenter.default.post(name: .memosDidChange, object: nil)
                }

                await MainActor.run {
                    if shouldEnqueue {
                        clearDraftAndEditor()
                        statusPresentation = .info(I18n.localized("memos_status_staged_sync", language: appState.language))
                    } else {
                        statusPresentation = QuickMemoSaveFailurePresenter.presentation(for: error)
                    }
                    isSaving = false
                }
            }
        }
    }

    private func shouldEnqueueCreate(after error: Error) -> Bool {
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

    private func handleStatusAction(_ presentation: QuickMemoStatusPresentation) {
        guard presentation.opensMemosSettings else {
            return
        }

        appState.settingsNavigationTarget = .memos
        NotificationCenter.default.post(name: NSNotification.Name("OpenSettingsWindow"), object: nil)
    }

    @MainActor
    private func handleDroppedFiles(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        
        _ = provider.loadObject(ofClass: URL.self) { url, error in
            guard let fileURL = url, error == nil else { return }
            
            guard let utType = UTType(filenameExtension: fileURL.pathExtension),
                  utType.conforms(to: .image) else { return }
            
            Task { @MainActor in
                // Offload file I/O to background thread
                guard let data = try? await Task.detached(priority: .userInitiated, operation: {
                    try Data(contentsOf: fileURL)
                }).value else { return }
                
                let filename = fileURL.lastPathComponent
                let mimeType = utType.preferredMIMEType ?? "image/png"
                
                await performAttachmentUpload(data: data, filename: filename, mimeType: mimeType)
            }
        }
        return true
    }

    @MainActor
    private func selectImageAndUpload() {
        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canCreateDirectories = false
        openPanel.allowedContentTypes = [.image]
        
        openPanel.begin { response in
            guard response == .OK, let fileURL = openPanel.url else { return }
            let utType = UTType(filenameExtension: fileURL.pathExtension) ?? .image
            
            Task {
                // Offload file I/O to background thread
                guard let data = try? await Task.detached(priority: .userInitiated, operation: {
                    try Data(contentsOf: fileURL)
                }).value else { return }
                
                let filename = fileURL.lastPathComponent
                let mimeType = utType.preferredMIMEType ?? "image/png"
                
                await performAttachmentUpload(data: data, filename: filename, mimeType: mimeType)
            }
        }
    }

    @MainActor
    private func pasteImageAndUpload() {
        Task {
            if let (data, filename, mimeType) = await uploadManager.handlePasteboardImage() {
                await performAttachmentUpload(data: data, filename: filename, mimeType: mimeType)
            }
        }
    }

    @MainActor
    private func performAttachmentUpload(data: Data, filename: String, mimeType: String) async {
        statusPresentation = nil
        do {
            let attachment = try await uploadManager.uploadImage(data: data, filename: filename, mimeType: mimeType)
            uploadedAttachments.append(attachment)
        } catch {
            let format = I18n.localized("memos_error_upload_failed", language: appState.language)
            statusPresentation = .error(String(format: format, error.localizedDescription))
        }
    }
}

// MARK: - TextEditorConfigurator
struct TextEditorConfigurator: NSViewRepresentable {
    var onConfigure: (NSScrollView) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let scrollView = findScrollView(for: view) {
                onConfigure(scrollView)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let scrollView = findScrollView(for: nsView) {
                onConfigure(scrollView)
            }
        }
    }

    private func findScrollView(for view: NSView) -> NSScrollView? {
        if let parent = view.superview {
            if let scrollView = parent as? NSScrollView {
                return scrollView
            }
            if let scrollView = findScrollView(in: parent, depth: 2, excluding: view) {
                return scrollView
            }
            if let grandparent = parent.superview {
                if let scrollView = grandparent as? NSScrollView {
                    return scrollView
                }
                if let scrollView = findScrollView(in: grandparent, depth: 2, excluding: parent) {
                    return scrollView
                }
            }
        }
        return nil
    }

    private func findScrollView(in view: NSView, depth: Int, excluding: NSView? = nil) -> NSScrollView? {
        if let scrollView = view as? NSScrollView {
            return scrollView
        }
        if depth <= 0 {
            return nil
        }
        for subview in view.subviews {
            if subview === excluding { continue }
            if let scrollView = subview as? NSScrollView {
                return scrollView
            }
            if let found = findScrollView(in: subview, depth: depth - 1) {
                return found
            }
        }
        return nil
    }
}
