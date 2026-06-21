import AppKit
import SwiftUI

public struct ClipboardPanelView: View {
    @ObservedObject private var viewModel: ClipboardPanelViewModel
    private let language: AppState.AppLanguage
    private let onChoose: (Int) -> Void
    @State private var showingClearUnpinnedConfirmation = false

    public init(
        viewModel: ClipboardPanelViewModel,
        language: AppState.AppLanguage = .system,
        onChoose: @escaping (Int) -> Void
    ) {
        self.viewModel = viewModel
        self.language = language
        self.onChoose = onChoose
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                listColumn
                    .frame(width: 380)
                Divider()
                ClipboardPreviewPane(
                    item: viewModel.selectedItem,
                    metadata: viewModel.selectedPreviewMetadata,
                    language: language
                )
                .frame(width: 220)
            }
        }
        .frame(width: 600, height: 620, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.10))
        .overlay {
            if showingClearUnpinnedConfirmation {
                clearConfirmationOverlay
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(localized("settings_tab_clipboard"))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)

            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)

                Text(viewModel.searchText.isEmpty ? localized("clipboard_panel_search_placeholder") : viewModel.searchText)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(viewModel.searchText.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.06))
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var listColumn: some View {
        VStack(spacing: 0) {
            listContent
            Divider()
            footer
        }
    }

    @ViewBuilder
    private var listContent: some View {
        if viewModel.filteredRows.isEmpty {
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: viewModel.searchText.isEmpty ? "clipboard" : "magnifyingglass")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(.tertiary)
                Text(viewModel.searchText.isEmpty ? localized("clipboard_panel_empty_history") : localized("clipboard_panel_no_matches"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: true) {
                    VStack(spacing: 0) {
                        ForEach(viewModel.filteredRows) { row in
                            rowView(row)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .onChange(of: viewModel.shouldScroll) { _, shouldScroll in
                    guard shouldScroll else { return }
                    if let selectedRowID = viewModel.selectedRowID {
                        withAnimation(.easeOut(duration: 0.12)) {
                            proxy.scrollTo(selectedRowID, anchor: .center)
                        }
                    }
                    viewModel.shouldScroll = false
                }
            }
        }
    }

    private func rowView(_ row: ClipboardPanelRowModel) -> some View {
        ClipboardPanelRow(
            item: row.item,
            index: row.filteredIndex,
            isSelected: row.filteredIndex == viewModel.selectedIndex,
            language: language,
            onTogglePinned: {
                viewModel.selectIndex(row.filteredIndex, scroll: false)
                viewModel.togglePinnedSelected()
            }
        )
        .id(row.id)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            onChoose(row.filteredIndex)
        }
        .onHover { hovering in
            if hovering {
                viewModel.selectIndex(row.filteredIndex, scroll: false)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            footerButton(
                title: localized("clipboard_panel_clear"),
                shortcut: nil,
                systemImage: "trash",
                role: .destructive
            ) {
                showingClearUnpinnedConfirmation = true
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var clearConfirmationOverlay: some View {
        ZStack {
            Color.black.opacity(0.16)
                .ignoresSafeArea()
                .onTapGesture {
                    showingClearUnpinnedConfirmation = false
                }

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(localized("clipboard_clear_unpinned_confirm_title"))
                        .font(.system(size: 17, weight: .semibold))
                    Text(localized("clipboard_clear_unpinned_confirm_message"))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 10) {
                    Button {
                        showingClearUnpinnedConfirmation = false
                    } label: {
                        Text(localized("keydrop_cancel_btn"))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Button(role: .destructive) {
                        viewModel.clearUnpinned()
                        showingClearUnpinnedConfirmation = false
                    } label: {
                        Text(localized("clipboard_clear_unpinned"))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding(20)
            .frame(width: 360)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .windowBackgroundColor))
            )
            .shadow(color: .black.opacity(0.22), radius: 24, y: 12)
        }
    }

    private func footerButton(
        title: String,
        shortcut: String?,
        systemImage: String,
        role: ButtonRole?,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            footerRow(title: title, shortcut: shortcut, systemImage: systemImage)
        }
        .buttonStyle(.plain)
    }

    private func footerRow(title: String, shortcut: String?, systemImage: String?) -> some View {
        HStack(spacing: 9) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 18)
            } else {
                Color.clear.frame(width: 18, height: 1)
            }

            Text(title)
                .font(.system(size: 13))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let shortcut {
                Text(shortcut)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: 26)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
    }

    private func localized(_ key: String) -> String {
        I18n.localized(key, language: language)
    }
}

private struct ClipboardPanelRow: View {
    let item: ClipboardItem
    let index: Int
    let isSelected: Bool
    let language: AppState.AppLanguage
    let onTogglePinned: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            thumbnail

            VStack(alignment: .leading, spacing: 2) {
                Text(item.localizedDisplayTitle(language: language))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(isSelected ? .white : .primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let secondaryText {
                    Text(secondaryText)
                        .font(.system(size: 11))
                        .foregroundStyle(isSelected ? .white.opacity(0.72) : .secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .layoutPriority(1)

            Button(action: onTogglePinned) {
                Image(systemName: item.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .foregroundStyle(isSelected ? .white.opacity(0.62) : .secondary.opacity(0.7))
            .opacity(isSelected || item.isPinned ? 1 : 0)
            .allowsHitTesting(isSelected || item.isPinned)
            .help(item.isPinned ? localized("clipboard_panel_unpin_item") : localized("clipboard_panel_pin_item"))

            shortcutText
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 34, maxHeight: 34, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor : Color.clear)
        )
        .clipped()
    }

    @ViewBuilder
    private var thumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(isSelected ? Color.white.opacity(0.16) : Color.primary.opacity(0.06))

            Image(systemName: iconName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isSelected ? .white.opacity(0.95) : .secondary)
        }
        .frame(width: 30, height: 24)
        .overlay {
            if let image = item.previewImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 30, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .clipped()
    }

    private var shortcutText: some View {
        Group {
            if index < 9 {
                Text("⌘\(index + 1)")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)
                    .frame(width: 32, alignment: .trailing)
            } else {
                Color.clear.frame(width: 32, height: 1)
            }
        }
    }

    private var secondaryText: String? {
        let source = item.sourceApplicationName
            ?? item.sourceBundleIdentifier?.split(separator: ".").last.map(String.init)
        let copied = item.copyCount > 1
            ? I18n.localizedFormat("clipboard_panel_copies_count", language: language, item.copyCount)
            : nil
        let time = item.lastCopiedAt.formatted(date: .omitted, time: .shortened)
        let parts = [source, copied, time].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var iconName: String {
        switch item.primaryKind {
        case .text:
            return "text.alignleft"
        case .richText:
            return "doc.richtext"
        case .image:
            return "photo"
        case .file:
            return "doc"
        case .mixed:
            return "square.stack.3d.up"
        case .unknown:
            return "questionmark.square"
        }
    }

    private func localized(_ key: String) -> String {
        I18n.localized(key, language: language)
    }
}

private struct ClipboardPreviewPane: View {
    let item: ClipboardItem?
    let metadata: ClipboardPreviewMetadata?
    let language: AppState.AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let item {
                previewHeader(for: item)
                Divider()
                metadataRows
                Spacer()
                keyboardHints
            } else {
                Spacer()
                Text(localized("clipboard_panel_no_selection"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            }
        }
        .padding(14)
    }

    private func previewHeader(for item: ClipboardItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.05))

                if item.primaryKind == .image {
                    if let image = item.previewImage {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .padding(8)
                    } else {
                        Image(systemName: "photo")
                            .font(.system(size: 30, weight: .regular))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(item.primaryPreview)
                        .font(.system(size: 12))
                        .foregroundStyle(.primary)
                        .lineLimit(8)
                        .multilineTextAlignment(.leading)
                        .padding(10)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .frame(height: 124)

            Text(item.localizedDisplayTitle(language: language))
                .font(.system(size: 13, weight: .medium))
                .lineLimit(2)
        }
    }

    @ViewBuilder
    private var metadataRows: some View {
        if let sourceName = metadata?.sourceName {
            metadataRow(localized("clipboard_panel_application"), sourceName)
        }

        if let metadata {
            metadataRow(
                localized("clipboard_panel_first_copied"),
                metadata.firstCopiedAt.formatted(date: .abbreviated, time: .shortened)
            )
            metadataRow(
                localized("clipboard_panel_last_copied"),
                metadata.lastCopiedAt.formatted(date: .abbreviated, time: .shortened)
            )
            metadataRow(localized("clipboard_panel_copies"), "\(metadata.copyCount)")
        }
    }

    private func metadataRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .lineLimit(2)
        }
    }

    private var keyboardHints: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(localized("clipboard_panel_hint_choose"))
            Text(localized("clipboard_panel_hint_pin"))
            Text(localized("clipboard_panel_hint_delete"))
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }

    private func localized(_ key: String) -> String {
        I18n.localized(key, language: language)
    }
}

private extension ClipboardItem {
    func localizedDisplayTitle(language: AppState.AppLanguage) -> String {
        if primaryKind == .image, title == "Image" {
            return I18n.localized("clipboard_item_image", language: language)
        }

        if title == "Clipboard Item" {
            return I18n.localized("clipboard_item_generic", language: language)
        }

        return title
    }

    var previewImage: NSImage? {
        contents.lazy.compactMap { content -> NSImage? in
            guard content.kind == .image else {
                return nil
            }

            switch content.storage {
            case let .inlineData(data):
                return NSImage(data: data)
            case .inlineText, .asset:
                return nil
            }
        }
        .first
    }
}
