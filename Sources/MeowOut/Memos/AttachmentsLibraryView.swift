import SwiftUI
import MemosKit
import AppKit

struct AttachmentsLibraryView: View {
    @Environment(AppState.self) private var appState
    enum AttachmentTab: String, CaseIterable, Identifiable {
        case media = "Media"
        case audio = "Audio"
        case documents = "Documents"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .media:
                "photo"
            case .audio:
                "waveform"
            case .documents:
                "doc"
            }
        }
    }

    @State private var selectedTab: AttachmentTab = .media
    @State private var attachments: [Attachment] = []
    @State private var isLoading = false
    @State private var errorMessage: String? = nil

    private var mediaAttachments: [Attachment] {
        attachments.filter { $0.isImage || $0.isVideo }
    }
    private var audioAttachments: [Attachment] {
        attachments.filter { $0.isAudio }
    }
    private var documentAttachments: [Attachment] {
        attachments.filter { !$0.isImage && !$0.isVideo && !$0.isAudio }
    }

    private var filteredAttachments: [Attachment] {
        switch selectedTab {
        case .media: return mediaAttachments
        case .audio: return audioAttachments
        case .documents: return documentAttachments
        }
    }

    // Group media attachments by Year & Month (e.g. "2026年5月")
    private var groupedMediaAttachments: [(String, [Attachment])] {
        let dict = Dictionary(grouping: mediaAttachments) { attachment -> String in
            guard let date = attachment.createTime else { return "Other" }
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            return formatter.string(from: date)
        }
        
        let sortedKeys = dict.keys.sorted(by: >)
        
        let displayFormatter = DateFormatter()
        displayFormatter.dateFormat = "yyyy年M月"
        
        let inputFormatter = DateFormatter()
        inputFormatter.dateFormat = "yyyy-MM"
        inputFormatter.locale = Locale(identifier: "en_US_POSIX")
        
        return sortedKeys.map { key in
            let displayTitle: String
            if key == "Other" {
                displayTitle = "其他"
            } else if let date = inputFormatter.date(from: key) {
                displayTitle = displayFormatter.string(from: date)
            } else {
                displayTitle = key
            }
            return (displayTitle, dict[key] ?? [])
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack(spacing: 12) {
                Text(I18n.localized("memos_category_attachments", language: appState.language))
                    .font(.system(size: 28, weight: .bold))

                Picker("", selection: $selectedTab) {
                    Text("Media (\(mediaAttachments.count))").tag(AttachmentTab.media)
                    Text("Audio (\(audioAttachments.count))").tag(AttachmentTab.audio)
                    Text("Documents (\(documentAttachments.count))").tag(AttachmentTab.documents)
                }
                .pickerStyle(.segmented)
                .frame(width: 380)
                .accessibilityLabel("附件类型")

                Spacer()

                Button {
                    loadAttachments()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("刷新")
                .accessibilityLabel("刷新附件")
            }

            // Main Content Area
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("正在加载附件...")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 36))
                        .foregroundStyle(.red)
                    Text("加载失败: \(error)")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Button("重试") { loadAttachments() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredAttachments.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: selectedTab.systemImage)
                        .font(.system(size: 44))
                        .foregroundStyle(.secondary)

                    Text(selectedTab.rawValue)
                        .font(.headline)

                    Text("暂无附件")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                switch selectedTab {
                case .media:
                    mediaGridView
                case .audio:
                    audioListView
                case .documents:
                    documentListView
                }
            }
        }
        .padding(28)
        .onAppear {
            loadAttachments()
        }
        .onReceive(NotificationCenter.default.publisher(for: .memosDidChange)) { _ in
            loadAttachments()
        }
    }

    private var mediaGridView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                ForEach(groupedMediaAttachments, id: \.0) { group in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(group.0)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                        
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 16)], spacing: 16) {
                            ForEach(group.1, id: \.name) { attachment in
                                AttachmentCardView(attachment: attachment) {
                                    appState.activeImageURL = fileURL(for: attachment)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var audioListView: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(audioAttachments, id: \.name) { attachment in
                    let url = fileURL(for: attachment)
                    Button(action: { NSWorkspace.shared.open(url) }) {
                        HStack(spacing: 12) {
                            Image(systemName: "waveform")
                                .font(.system(size: 18))
                                .foregroundStyle(.secondary)
                                .frame(width: 40, height: 40)
                                .background(Color.primary.opacity(0.04))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(attachment.filename)
                                    .font(.system(size: 13, weight: .medium))
                                    .lineLimit(1)
                                Text(ByteCountFormatter.string(fromByteCount: attachment.size, countStyle: .file))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.primary.opacity(0.02))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .help(attachment.filename)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var documentListView: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(documentAttachments, id: \.name) { attachment in
                    let url = fileURL(for: attachment)
                    Button(action: { NSWorkspace.shared.open(url) }) {
                        HStack(spacing: 12) {
                            Image(systemName: fileIconName(for: attachment.type))
                                .font(.system(size: 18))
                                .foregroundStyle(.secondary)
                                .frame(width: 40, height: 40)
                                .background(Color.primary.opacity(0.04))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(attachment.filename)
                                    .font(.system(size: 13, weight: .medium))
                                    .lineLimit(1)
                                Text(ByteCountFormatter.string(fromByteCount: attachment.size, countStyle: .file))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.primary.opacity(0.02))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .help(attachment.filename)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func loadAttachments() {
        guard MemosClient.shared.isConfigured else { return }
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let list = try await MemosClient.shared.listAllAttachments()
                await MainActor.run {
                    self.attachments = list
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    private func fileURL(for attachment: Attachment) -> URL {
        let baseURL = appState.memosBaseURL ?? URL(string: "http://localhost:8081")!
        return baseURL.appendingPathComponent("file/\(attachment.name)/\(attachment.filename)")
    }

    private func fileIconName(for mimeType: String) -> String {
        if mimeType.contains("pdf") {
            return "doc.richtext"
        } else {
            return "doc"
        }
    }
}

struct AttachmentCardView: View {
    @Environment(AppState.self) private var appState
    let attachment: Attachment
    let onPreview: () -> Void

    private var fileURL: URL {
        let baseURL = appState.memosBaseURL ?? URL(string: "http://localhost:8081")!
        return baseURL.appendingPathComponent("file/\(attachment.name)/\(attachment.filename)")
    }

    private var formattedDate: String {
        guard let date = attachment.createTime else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月d日"
        return formatter.string(from: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Preview / Thumbnail
            Button(action: onPreview) {
                if attachment.isImage {
                    Color.clear
                        .frame(height: 140)
                        .overlay(
                            MemosAttachmentImageView(url: fileURL, contentMode: .fill)
                        )
                        .clipped()
                } else {
                    ZStack {
                        Color.primary.opacity(0.04)
                        VStack(spacing: 8) {
                            Image(systemName: "video.fill")
                                .font(.system(size: 28))
                            Text(attachment.filename)
                                .font(.system(size: 10))
                                .lineLimit(1)
                                .padding(.horizontal, 8)
                        }
                        .foregroundStyle(.secondary)
                    }
                    .frame(height: 140)
                }
            }
            .buttonStyle(.plain)

            Divider()

            // Info Section
            VStack(alignment: .leading, spacing: 6) {
                Text(attachment.filename)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack {
                    Text("\(attachment.type.split(separator: "/").last?.uppercased() ?? "PNG") · \(formattedDate)")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button(action: {
                        NSWorkspace.shared.open(fileURL)
                    }) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("在浏览器中打开")
                }
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.02), radius: 4, x: 0, y: 2)
    }
}
