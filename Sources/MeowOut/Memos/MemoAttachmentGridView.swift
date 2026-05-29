import SwiftUI
import MemosKit
import AppKit

struct MemoAttachmentGridView: View {
    @Environment(AppState.self) private var appState
    let attachments: [Attachment]

    private var mediaAttachments: [Attachment] {
        attachments.filter { $0.isImage || $0.isVideo }
    }

    private var fileAttachments: [Attachment] {
        attachments.filter { !$0.isImage && !$0.isVideo }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Media Grid/List (Images and Videos)
            if !mediaAttachments.isEmpty {
                if mediaAttachments.count == 1 {
                    let attachment = mediaAttachments[0]
                    let url = fileURL(for: attachment)
                    Button(action: {
                        if attachment.isImage {
                            appState.activeImageURL = url
                        } else {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        if attachment.isImage {
                            MemosAttachmentImageView(url: url, contentMode: .fit)
                                .frame(maxHeight: 320)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                                )
                        } else {
                            // Video Placeholder
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.primary.opacity(0.05))
                                    .frame(width: 180, height: 120)
                                Image(systemName: "video.fill")
                                    .font(.system(size: 32))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .help(attachment.filename)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(mediaAttachments, id: \.name) { attachment in
                                let url = fileURL(for: attachment)
                                Button(action: {
                                    if attachment.isImage {
                                        appState.activeImageURL = url
                                    } else {
                                        NSWorkspace.shared.open(url)
                                    }
                                }) {
                                    if attachment.isImage {
                                        Color.clear
                                            .frame(width: 120, height: 120)
                                            .overlay(
                                                MemosAttachmentImageView(url: url, contentMode: .fill)
                                            )
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    } else {
                                        // Video Placeholder
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Color.primary.opacity(0.05))
                                                .frame(width: 120, height: 120)
                                            Image(systemName: "video.fill")
                                                .font(.system(size: 28))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .help(attachment.filename)
                            }
                        }
                    }
                }
            }

            // File Cards (Documents, Audio, etc.)
            if !fileAttachments.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(fileAttachments, id: \.name) { attachment in
                        let url = fileURL(for: attachment)
                        Button(action: {
                            NSWorkspace.shared.open(url)
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: fileIconName(for: attachment.type))
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                Text(attachment.filename)
                                    .font(.system(size: 11))
                                    .lineLimit(1)
                                Text(ByteCountFormatter.string(fromByteCount: attachment.size, countStyle: .file))
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(0.04))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .help(attachment.filename)
                    }
                }
            }
        }
    }

    private func fileURL(for attachment: Attachment) -> URL {
        let baseURL = appState.memosBaseURL ?? URL(string: "http://localhost:8081")!
        return baseURL.appendingPathComponent("file/\(attachment.name)/\(attachment.filename)")
    }

    private func fileIconName(for mimeType: String) -> String {
        if mimeType.hasPrefix("audio/") {
            return "waveform"
        } else if mimeType.contains("pdf") {
            return "doc.richtext"
        } else {
            return "doc"
        }
    }
}
