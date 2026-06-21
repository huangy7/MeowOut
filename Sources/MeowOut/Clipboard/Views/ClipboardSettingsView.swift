import ApplicationServices
import KeyboardShortcuts
import SwiftUI

struct ClipboardSettingsView: View {
    @Environment(AppState.self) private var appState
    @ObservedObject private var store = ClipboardHistoryStore.shared

    let selectedTab: String

    @State private var ignoredApplications: [String] = []
    @State private var ignoredPasteboardTypes: [String] = []
    @State private var newIgnoredApplication = ""
    @State private var newIgnoredPasteboardType = ""
    @State private var showingRestoreIgnoredTypesConfirmation = false
    @State private var showingClearUnpinnedConfirmation = false
    @State private var showingClearAllConfirmation = false
    @State private var isAccessibilityTrusted = AXIsProcessTrusted()
    @State private var settingsRevision = 0

    private let settings = ClipboardHistorySettings.shared

    private var pinnedItems: [ClipboardItem] {
        store.items.filter(\.isPinned)
    }

    var body: some View {
        Group {
            switch selectedTab {
            case "storage":
                storageCards
            case "pinned":
                pinnedCards
            case "ignored":
                ignoredCards
            default:
                generalCards
            }
        }
        .id(settingsRevision)
        .onAppear {
            refreshLists()
            refreshAccessibilityStatus()
            applyClipboardEnabledState()
        }
        .alert(I18n.localized("clipboard_restore_ignored_types_confirm_title", language: appState.language), isPresented: $showingRestoreIgnoredTypesConfirmation) {
            Button(I18n.localized("keydrop_cancel_btn", language: appState.language), role: .cancel) { }
            Button(I18n.localized("clipboard_restore_ignored_types", language: appState.language), role: .destructive) {
                settings.restoreDefaultIgnoredPasteboardTypes()
                refreshLists()
            }
        } message: {
            Text(I18n.localized("clipboard_restore_ignored_types_confirm_message", language: appState.language))
        }
        .alert(I18n.localized("clipboard_clear_unpinned_confirm_title", language: appState.language), isPresented: $showingClearUnpinnedConfirmation) {
            Button(I18n.localized("keydrop_cancel_btn", language: appState.language), role: .cancel) { }
            Button(I18n.localized("clipboard_clear_unpinned", language: appState.language), role: .destructive) {
                ClipboardHistoryStore.shared.clearUnpinned()
            }
        } message: {
            Text(I18n.localized("clipboard_clear_unpinned_confirm_message", language: appState.language))
        }
        .alert(I18n.localized("clipboard_clear_all_confirm_title", language: appState.language), isPresented: $showingClearAllConfirmation) {
            Button(I18n.localized("keydrop_cancel_btn", language: appState.language), role: .cancel) { }
            Button(I18n.localized("clipboard_clear_all", language: appState.language), role: .destructive) {
                ClipboardHistoryStore.shared.clearAll()
            }
        } message: {
            Text(I18n.localized("clipboard_clear_all_confirm_message", language: appState.language))
        }
    }

    private var generalCards: some View {
        Group {
            SettingsCard(
                icon: "clipboard",
                iconColor: .green,
                title: I18n.localized("clipboard_enabled", language: appState.language),
                description: I18n.localized("clipboard_enabled_desc", language: appState.language)
            ) {
                VStack(spacing: 12) {
                    settingsRow(I18n.localized("clipboard_enabled", language: appState.language)) {
                        Toggle("", isOn: enabledBinding)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }

                    settingsRow(I18n.localized("clipboard_shortcut", language: appState.language)) {
                        KeyboardShortcuts.Recorder(for: .toggleClipboardHistoryPanel)
                            .disabled(!settings.isEnabled)
                            .opacity(settings.isEnabled ? 1 : 0.45)
                    }
                }
            }

            SettingsCard(
                icon: "arrowshape.turn.up.left",
                iconColor: .purple,
                title: I18n.localized("clipboard_behavior", language: appState.language),
                description: nil
            ) {
                VStack(spacing: 12) {
                    settingsRow(I18n.localized("clipboard_paste_automatically", language: appState.language)) {
                        Toggle("", isOn: pasteAutomaticallyBinding)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }

                    settingsRow(I18n.localized("clipboard_accessibility_permission", language: appState.language)) {
                        HStack(spacing: 10) {
                            Label(
                                isAccessibilityTrusted
                                    ? I18n.localized("clipboard_accessibility_granted", language: appState.language)
                                    : I18n.localized("clipboard_accessibility_missing", language: appState.language),
                                systemImage: isAccessibilityTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                            )
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(isAccessibilityTrusted ? Color.green : Color.orange)

                            Button(I18n.localized("clipboard_request_accessibility", language: appState.language)) {
                                requestAccessibilityPermission(prompt: true)
                            }
                            .disabled(isAccessibilityTrusted)
                        }
                    }

                    settingsRow(I18n.localized("clipboard_paste_plain_text_by_default", language: appState.language)) {
                        Toggle("", isOn: boolBinding(\.removeFormattingByDefault))
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }

                    Text(I18n.localized("clipboard_paste_plain_text_help", language: appState.language))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var storageCards: some View {
        Group {
            SettingsCard(
                icon: "tray.and.arrow.down",
                iconColor: .orange,
                title: I18n.localized("clipboard_record_types", language: appState.language),
                description: nil
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(I18n.localized("clipboard_record_files", language: appState.language), isOn: boolBinding(\.recordFiles))
                    Toggle(I18n.localized("clipboard_record_images", language: appState.language), isOn: boolBinding(\.recordImages))
                    Toggle(I18n.localized("clipboard_record_text", language: appState.language), isOn: recordTextBinding)
                }
                .toggleStyle(.checkbox)
            }

            SettingsCard(
                icon: "archivebox",
                iconColor: .blue,
                title: I18n.localized("clipboard_storage", language: appState.language),
                description: nil
            ) {
                VStack(spacing: 12) {
                    settingsRow(I18n.localized("clipboard_history_limit", language: appState.language)) {
                        Stepper(value: intBinding(\.historyLimit), in: 1...999, step: 1) {
                            Text("\(settings.historyLimit)")
                                .frame(width: 54, alignment: .trailing)
                                .monospacedDigit()
                        }
                    }

                    settingsRow(I18n.localized("clipboard_sort_mode", language: appState.language)) {
                        Picker("", selection: sortModeBinding) {
                            Text(I18n.localized("clipboard_sort_last_copied", language: appState.language)).tag(ClipboardHistorySettings.SortMode.lastCopiedAt)
                            Text(I18n.localized("clipboard_sort_first_copied", language: appState.language)).tag(ClipboardHistorySettings.SortMode.createdAt)
                            Text(I18n.localized("clipboard_sort_copy_count", language: appState.language)).tag(ClipboardHistorySettings.SortMode.copyCount)
                        }
                        .labelsHidden()
                        .frame(width: 170)
                    }
                }
            }

            SettingsCard(
                icon: "trash",
                iconColor: .pink,
                title: I18n.localized("clipboard_management", language: appState.language),
                description: nil
            ) {
                HStack(spacing: 10) {
                    Button(I18n.localized("clipboard_clear_unpinned", language: appState.language), role: .destructive) {
                        showingClearUnpinnedConfirmation = true
                    }

                    Button(I18n.localized("clipboard_clear_all", language: appState.language), role: .destructive) {
                        showingClearAllConfirmation = true
                    }
                }
            }
        }
    }

    private var pinnedCards: some View {
        SettingsCard(
            icon: "pin",
            iconColor: .purple,
            title: I18n.localized("clipboard_tab_pinned", language: appState.language),
            description: I18n.localized("clipboard_pinned_desc", language: appState.language)
        ) {
            if pinnedItems.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "pin.slash")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(.tertiary)
                    Text(I18n.localized("clipboard_no_pinned_items", language: appState.language))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
            } else {
                VStack(spacing: 8) {
                    ForEach(pinnedItems) { item in
                        pinnedItemRow(item)
                    }
                }
            }
        }
    }

    private var ignoredCards: some View {
        Group {
            SettingsCard(
                icon: "app.badge",
                iconColor: .red,
                title: I18n.localized("clipboard_ignored_apps", language: appState.language),
                description: nil
            ) {
                editableList(
                    placeholder: I18n.localized("clipboard_ignored_apps_placeholder", language: appState.language),
                    values: ignoredApplications,
                    newValue: $newIgnoredApplication,
                    add: addIgnoredApplication,
                    remove: removeIgnoredApplication
                )
            }

            SettingsCard(
                icon: "doc.badge.gearshape",
                iconColor: .orange,
                title: I18n.localized("clipboard_ignored_types", language: appState.language),
                description: I18n.localized("clipboard_ignored_types_desc", language: appState.language)
            ) {
                editableList(
                    placeholder: I18n.localized("clipboard_ignored_types_placeholder", language: appState.language),
                    values: ignoredPasteboardTypes,
                    newValue: $newIgnoredPasteboardType,
                    add: addIgnoredPasteboardType,
                    remove: removeIgnoredPasteboardType
                )

                Button(I18n.localized("clipboard_restore_ignored_types", language: appState.language)) {
                    showingRestoreIgnoredTypesConfirmation = true
                }
            }
        }
    }

    private func settingsRow<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 150, alignment: .leading)
            Spacer(minLength: 0)
            content()
        }
    }

    private func editableList(
        placeholder: String,
        values: [String],
        newValue: Binding<String>,
        add: @escaping () -> Void,
        remove: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField(placeholder, text: newValue)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)

                Button(action: add) {
                    Image(systemName: "plus")
                }
                .help(I18n.localized("clipboard_add", language: appState.language))
                .disabled(newValue.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if !values.isEmpty {
                VStack(spacing: 6) {
                    ForEach(values, id: \.self) { value in
                        HStack(spacing: 8) {
                            Text(value)
                                .font(.system(size: 11))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button {
                                remove(value)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help(I18n.localized("clipboard_delete", language: appState.language))
                        }
                    }
                }
            }
        }
    }

    private func pinnedItemRow(_ item: ClipboardItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: iconName(for: item))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .background(Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(displayTitle(for: item))
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 6) {
                    if let source = item.sourceApplicationName ?? item.sourceBundleIdentifier {
                        Text(source)
                    }
                    Text(I18n.localizedFormat("clipboard_panel_copies_count", language: appState.language, item.copyCount))
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button {
                store.togglePinned(item.id)
            } label: {
                Image(systemName: "pin.slash")
            }
            .buttonStyle(.plain)
            .help(I18n.localized("clipboard_unpin", language: appState.language))

            Button(role: .destructive) {
                store.delete(item.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .help(I18n.localized("clipboard_delete", language: appState.language))
        }
        .padding(8)
        .background(Color.primary.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func iconName(for item: ClipboardItem) -> String {
        switch item.primaryKind {
        case .image:
            return "photo"
        case .file:
            return "doc"
        case .richText:
            return "textformat"
        case .text:
            return "text.alignleft"
        case .mixed:
            return "square.stack"
        case .unknown:
            return "questionmark.square"
        }
    }

    private func displayTitle(for item: ClipboardItem) -> String {
        if item.primaryKind == .image, item.title == "Image" {
            return I18n.localized("clipboard_item_image", language: appState.language)
        }

        if item.title == "Clipboard Item" {
            return I18n.localized("clipboard_item_generic", language: appState.language)
        }

        return item.title
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { settings.isEnabled },
            set: { isEnabled in
                settings.isEnabled = isEnabled
                settingsRevision += 1
                applyClipboardEnabledState()
            }
        )
    }

    private var pasteAutomaticallyBinding: Binding<Bool> {
        Binding(
            get: { settings.pasteAutomatically },
            set: { enabled in
                settings.pasteAutomatically = enabled
                settingsRevision += 1
                if enabled {
                    requestAccessibilityPermission(prompt: true)
                } else {
                    refreshAccessibilityStatus()
                }
            }
        )
    }

    private var recordTextBinding: Binding<Bool> {
        Binding(
            get: { settings.recordText },
            set: { enabled in
                settings.recordText = enabled
                settings.recordRichText = enabled
                settingsRevision += 1
            }
        )
    }

    private var sortModeBinding: Binding<ClipboardHistorySettings.SortMode> {
        Binding(
            get: { settings.sortMode },
            set: {
                settings.sortMode = $0
                settingsRevision += 1
            }
        )
    }

    private func boolBinding(_ keyPath: ReferenceWritableKeyPath<ClipboardHistorySettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: {
                settings[keyPath: keyPath] = $0
                settingsRevision += 1
            }
        )
    }

    private func intBinding(_ keyPath: ReferenceWritableKeyPath<ClipboardHistorySettings, Int>) -> Binding<Int> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: {
                settings[keyPath: keyPath] = $0
                settingsRevision += 1
            }
        )
    }

    private func applyClipboardEnabledState() {
        if settings.isEnabled {
            KeyboardShortcuts.enable(.toggleClipboardHistoryPanel)
            ClipboardMonitorService.shared.start()
        } else {
            KeyboardShortcuts.disable(.toggleClipboardHistoryPanel)
            ClipboardMonitorService.shared.stop()
            ClipboardPanelController.shared.hide()
        }
    }

    private func requestAccessibilityPermission(prompt: Bool) {
        if prompt {
            ClipboardAccessibilityPermission.requestAuthorizationPrompt()
        }
        refreshAccessibilityStatus()
    }

    private func refreshAccessibilityStatus() {
        isAccessibilityTrusted = AXIsProcessTrusted()
    }

    private func refreshLists() {
        ignoredApplications = settings.ignoredApplications.sorted()
        ignoredPasteboardTypes = settings.ignoredPasteboardTypes.sorted()
    }

    private func addIgnoredApplication() {
        add(newIgnoredApplication, to: \.ignoredApplications)
        newIgnoredApplication = ""
        refreshLists()
    }

    private func removeIgnoredApplication(_ value: String) {
        remove(value, from: \.ignoredApplications)
        refreshLists()
    }

    private func addIgnoredPasteboardType() {
        add(newIgnoredPasteboardType, to: \.ignoredPasteboardTypes)
        newIgnoredPasteboardType = ""
        refreshLists()
    }

    private func removeIgnoredPasteboardType(_ value: String) {
        remove(value, from: \.ignoredPasteboardTypes)
        refreshLists()
    }

    private func add(_ value: String, to keyPath: ReferenceWritableKeyPath<ClipboardHistorySettings, Set<String>>) {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else { return }
        var values = settings[keyPath: keyPath]
        values.insert(trimmedValue)
        settings[keyPath: keyPath] = values
    }

    private func remove(_ value: String, from keyPath: ReferenceWritableKeyPath<ClipboardHistorySettings, Set<String>>) {
        var values = settings[keyPath: keyPath]
        values.remove(value)
        settings[keyPath: keyPath] = values
    }
}
