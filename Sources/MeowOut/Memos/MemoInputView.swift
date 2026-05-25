import SwiftUI
import MemosKit

struct MemoInputView: View {
    @Environment(AppState.self) private var appState
    @Binding var inputText: String
    @Binding var selectedTags: Set<String>
    let availableTags: [String]
    let pendingCount: Int
    let isConfigured: Bool
    let onSend: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                if inputText.isEmpty {
                    Text("记点什么... (⌘↵ 发送)")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                }
                TextEditor(text: $inputText)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .focused($isFocused)
                    .frame(minHeight: 50, maxHeight: 120)
                    .disabled(!isConfigured)
            }

            HStack(spacing: 6) {
                ForEach(availableTags.prefix(6), id: \.self) { tag in
                    Button(action: { toggleTag(tag) }) {
                        Text("#\(tag)")
                            .font(.system(size: 11))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(selectedTags.contains(tag)
                                        ? Color.accentColor.opacity(0.2)
                                        : Color.secondary.opacity(0.1))
                            .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                if pendingCount > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.up.circle")
                            .font(.system(size: 10))
                        Text("\(pendingCount) 待发送")
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(.orange)
                }

                Button(action: onSend) {
                    HStack(spacing: 4) {
                        Text(I18n.localized("memos_action_send", language: appState.language))
                        Text("⌘↵").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(inputText.isEmpty ? 0.3 : 0.8))
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(12)
        .onAppear { isFocused = true }
    }

    private func toggleTag(_ tag: String) {
        if selectedTags.contains(tag) {
            selectedTags.remove(tag)
            inputText = inputText.replacingOccurrences(of: " #\(tag)", with: "")
            inputText = inputText.replacingOccurrences(of: "#\(tag)", with: "")
        } else {
            selectedTags.insert(tag)
            if !inputText.contains("#\(tag)") {
                inputText = inputText.trimmingCharacters(in: .whitespaces)
                inputText += (inputText.isEmpty ? "" : " ") + "#\(tag)"
            }
        }
    }
}
