import SwiftUI
import MemosKit
import NetworkImage

struct EditorAttachmentListView: View {
    @Environment(AppState.self) private var appState
    let attachments: [Attachment]
    let onRemove: (Attachment) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(I18n.localized("memos_category_attachments", language: appState.language)) (\(attachments.count))")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(attachments, id: \.name) { attachment in
                        EditorAttachmentCard(attachment: attachment, onRemove: {
                            onRemove(attachment)
                        })
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }
        }
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.02))
        .cornerRadius(8)
    }
}

struct EditorAttachmentCard: View {
    @Environment(AppState.self) private var appState
    let attachment: Attachment
    let onRemove: () -> Void

    private var fileURL: URL {
        let baseURL = appState.memosBaseURL ?? URL(string: "http://localhost:8081")!
        return baseURL.appendingPathComponent("file/\(attachment.name)/\(attachment.filename)")
    }

    private var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: attachment.size, countStyle: .file)
    }

    var body: some View {
        HStack(spacing: 8) {
            // Thumbnail / Icon
            if attachment.isImage {
                Color.clear
                    .frame(width: 32, height: 32)
                    .overlay(
                        MemosAttachmentImageView(url: fileURL, contentMode: .fill)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Image(systemName: fileIconName(for: attachment.type))
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            // Details
            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.filename)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .frame(maxWidth: 120, alignment: .leading)
                Text(formattedSize)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }

            // Remove Button
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
            .padding(.trailing, 2)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func fileIconName(for mimeType: String) -> String {
        if mimeType.hasPrefix("audio/") {
            return "waveform"
        } else if mimeType.hasPrefix("video/") {
            return "video"
        } else if mimeType.contains("pdf") {
            return "doc.richtext"
        } else {
            return "doc"
        }
    }
}
