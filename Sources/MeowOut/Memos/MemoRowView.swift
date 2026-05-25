import SwiftUI
import MemosKit

struct MemoRowView: View {
    let memo: Memo
    let onArchive: () -> Void
    let onUnarchive: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void
    let onEdit: () -> Void

    @Environment(AppState.self) private var appState
    @State private var showingDeleteAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: Time and Menu
            HStack {
                Text(relativeTime(memo.createTime))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
                
                if memo.pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                        .padding(.leading, 4)
                }
                
                Spacer()
                
                Menu {
                    Button(I18n.localized("memos_action_edit", language: appState.language), action: onEdit)
                    Divider()
                    if memo.state == .normal {
                        Button(I18n.localized("memos_action_archive", language: appState.language), action: onArchive)
                    } else {
                        Button(I18n.localized("memos_action_unarchive", language: appState.language), action: onUnarchive)
                    }
                    Button(memo.pinned ? I18n.localized("memos_action_unpin", language: appState.language) : I18n.localized("memos_action_pin", language: appState.language), action: onTogglePin)
                    Divider()
                    Button(I18n.localized("memos_action_delete", language: appState.language), role: .destructive) { showingDeleteAlert = true }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            
            // Content
            Text(memo.content)
                .font(.system(size: 13, weight: .regular))
                .lineSpacing(4)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
            
            // Tags
            if !memo.tags.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(memo.tags, id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.secondary.opacity(0.08))
                            .foregroundStyle(.secondary)
                            .cornerRadius(6)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.02), radius: 4, x: 0, y: 2)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .alert(I18n.localized("memo_delete_confirm_title", language: appState.language), isPresented: $showingDeleteAlert) {
            Button(I18n.localized("memo_delete_confirm_cancel", language: appState.language), role: .cancel) { }
            Button(I18n.localized("memo_delete_confirm_delete", language: appState.language), role: .destructive) { onDelete() }
        } message: {
            Text(I18n.localized("memo_delete_confirm_message", language: appState.language))
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: date)
        }
        
        let interval = Date().timeIntervalSince(date)
        if interval < 86400 * 7 {
            let formatter = DateFormatter()
            formatter.dateFormat = "MM-dd EEEE"
            return formatter.string(from: date)
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

struct PendingMemoRowView: View {
    let item: OfflineQueue.QueueItem
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack {
            if item.retryCount > 3 {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
            } else {
                Image(systemName: "clock")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            }
            if case .create(let content, _, _) = item.action {
                Text(String(content.prefix(80)))
                    .font(.system(size: 12))
                    .lineLimit(2)
            } else if case .update(let name, _, _, _) = item.action {
                Text(I18n.localizedFormat("memos_status_update_name", language: appState.language, name))
                    .font(.system(size: 12))
            } else if case .delete(let name) = item.action {
                Text(I18n.localizedFormat("memos_status_delete_name", language: appState.language, name))
                    .font(.system(size: 12))
            }
            Spacer()
            Text(item.retryCount > 3 ? I18n.localized("memos_status_failed", language: appState.language) : I18n.localized("memos_status_pending", language: appState.language))
                .font(.system(size: 10))
                .foregroundStyle(item.retryCount > 3 ? .red : .orange)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(item.retryCount > 3
                     ? Color.red.opacity(0.05)
                     : Color.orange.opacity(0.05))
        .contextMenu {
            if case .create(let content, let vis, _) = item.action {
                Button(I18n.localized("memos_action_send_archived", language: appState.language)) {
                    OfflineQueue.shared.updateItem(item.id, action: .create(
                        content: content, visibility: vis, archiveAfterCreate: true))
                }
            }
            Button(I18n.localized("memos_action_delete", language: appState.language), role: .destructive) {
                OfflineQueue.shared.removeItem(item.id)
            }
        }
    }
}
