import SwiftUI
import MemosKit

struct MemoEditorView: View {
    @Environment(AppState.self) private var appState
    @Binding var text: String
    @Binding var selectedTags: Set<String>
    @Binding var visibility: MemoVisibility
    let availableTags: [String]
    let placeholder: String
    let showsFocusButton: Bool
    let onFocus: (() -> Void)?
    let onSave: () -> Void

    @FocusState private var isFocused: Bool
    @State private var selectedCommand: MemoSlashCommand?

    private var trigger: MemoSlashCommandTrigger? {
        MemoSlashCommandTrigger.detect(in: text, cursorOffset: text.count)
    }

    private var matchingCommands: [MemoSlashCommand] {
        guard let trigger else { return [] }
        return MemoSlashCommand.matching(query: trigger.query)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                }
                TextEditor(text: $text)
                    .font(.system(size: 15))
                    .scrollContentBackground(.hidden)
                    .focused($isFocused)
                    .frame(minHeight: 86)
                    .onSubmit { onSave() }
            }

            if !matchingCommands.isEmpty {
                MemoSlashCommandMenu(
                    commands: matchingCommands,
                    selectedCommand: selectedCommand ?? matchingCommands.first,
                    onSelect: applyCommand)
            }

            HStack(spacing: 8) {
                ForEach(availableTags.prefix(6), id: \.self) { tag in
                    Button("#\(tag)") { toggleTag(tag) }
                        .buttonStyle(.borderless)
                        .foregroundStyle(selectedTags.contains(tag) ? Color.accentColor : Color.secondary)
                }

                Spacer()

                Picker("", selection: $visibility) {
                    Text(I18n.localized("memos_editor_visibility_private", language: appState.language)).tag(MemoVisibility.private)
                    Text(I18n.localized("memos_editor_visibility_protected", language: appState.language)).tag(MemoVisibility.protected)
                    Text(I18n.localized("memos_editor_visibility_public", language: appState.language)).tag(MemoVisibility.public)
                }
                .frame(width: 96)

                if showsFocusButton {
                    Button(action: { onFocus?() }) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                    }
                    .help("聚焦模式")
                }

                Button(I18n.localized("memos_action_save", language: appState.language), action: onSave)
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onAppear { isFocused = true }
    }

    private func applyCommand(_ command: MemoSlashCommand) {
        guard let trigger else { return }
        let result = command.apply(to: text, triggerRange: trigger.range)
        text = result.text
        selectedCommand = nil
    }

    private func toggleTag(_ tag: String) {
        if selectedTags.contains(tag) {
            selectedTags.remove(tag)
            text = text.replacingOccurrences(of: " #\(tag)", with: "")
            text = text.replacingOccurrences(of: "#\(tag)", with: "")
        } else {
            selectedTags.insert(tag)
            if !text.contains("#\(tag)") {
                text = text.trimmingCharacters(in: .whitespaces)
                text += (text.isEmpty ? "" : " ") + "#\(tag)"
            }
        }
    }
}
