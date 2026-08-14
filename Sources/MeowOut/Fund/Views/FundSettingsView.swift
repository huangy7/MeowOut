import SwiftUI
import KeyboardShortcuts
import UniformTypeIdentifiers
import AppKit

struct FundDropDelegate: DropDelegate {
    let item: FundConfig
    @Binding var draggedItem: FundConfig?

    func dropEntered(info: DropInfo) {
        guard let draggedItem = self.draggedItem else { return }
        guard draggedItem.code != item.code else { return }

        let store = FundConfigStore.shared
        guard let fromIndex = store.configs.firstIndex(where: { $0.code == draggedItem.code }),
              let toIndex = store.configs.firstIndex(where: { $0.code == item.code }) else { return }

        if fromIndex != toIndex {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                store.configs.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
            }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        self.draggedItem = nil
        FundConfigStore.shared.save()
        FundService.shared.reorderFunds(by: FundConfigStore.shared.configs.map(\.code))
        return true
    }
}

public struct FundSettingsView: View {
    @Environment(AppState.self) private var appState
    @ObservedObject private var configStore = FundConfigStore.shared
    @ObservedObject private var settings = FundSettings.shared
    @ObservedObject private var fundService = FundService.shared

    @State private var searchText: String = ""
    @State private var searchResults: [FundSearchResult] = []
    @State private var isSearching: Bool = false
    @State private var searchTask: Task<Void, Never>?
    @State private var draggedConfig: FundConfig?
    @State private var expandedCode: String?

    // Sync & Backup State
    @State private var toastMessage: String?
    @State private var pendingImportConfigs: [FundConfig]?
    @State private var isShowingImportDialog: Bool = false
    @State private var isShowingSyncAlert: Bool = false
    @State private var syncAlertMessage: String?
    @State private var isShowingManualPasteSheet: Bool = false
    @State private var manualPasteText: String = ""

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            searchCard
            if !configStore.configs.isEmpty {
                holdingsCard
            }
            settingsCard
        }
        .confirmationDialog(
            I18n.localized("fund_import_dialog_title", language: appState.language),
            isPresented: $isShowingImportDialog,
            titleVisibility: .visible
        ) {
            if let pending = pendingImportConfigs {
                Button(I18n.localized("fund_import_mode_replace", language: appState.language)) {
                    let count = configStore.importConfigs(pending, mode: .replace)
                    showToast(I18n.localizedFormat("fund_import_success", language: appState.language, count))
                    pendingImportConfigs = nil
                }
                Button(I18n.localized("fund_import_mode_merge", language: appState.language)) {
                    let count = configStore.importConfigs(pending, mode: .merge)
                    showToast(I18n.localizedFormat("fund_import_success", language: appState.language, count))
                    pendingImportConfigs = nil
                }
                Button(I18n.localized("fund_cancel", language: appState.language), role: .cancel) {
                    pendingImportConfigs = nil
                }
            }
        } message: {
            if let pending = pendingImportConfigs {
                Text(I18n.localizedFormat("fund_import_dialog_message", language: appState.language, pending.count))
            }
        }
        .alert(
            I18n.localized("fund_sync_title", language: appState.language),
            isPresented: $isShowingSyncAlert
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            if let msg = syncAlertMessage {
                Text(msg)
            }
        }
        .sheet(isPresented: $isShowingManualPasteSheet) {
            manualPasteSheetView
        }
    }

    // MARK: - Search & Add Card (with Multi-device Sync)

    private var searchCard: some View {
        SettingsCard(
            icon: "plus.magnifyingglass",
            iconColor: .blue,
            title: I18n.localized("fund_add_title", language: appState.language),
            description: I18n.localized("fund_add_desc", language: appState.language)
        ) {
            VStack(alignment: .leading, spacing: 8) {
                // 搜索框
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))
                    TextField(I18n.localized("fund_search_placeholder", language: appState.language), text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .onChange(of: searchText) { _, newValue in
                            performSearch(keyword: newValue)
                        }

                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                            searchResults = []
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(8)

                // 快捷导入与导出栏
                HStack(spacing: 8) {
                    // 从剪贴板导入
                    Button(action: importConfigFromClipboard) {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.down")
                            Text(I18n.localized("fund_import_btn", language: appState.language))
                        }
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.12))
                        .foregroundStyle(Color.accentColor)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)

                    // 复制配置
                    Button(action: exportConfigToClipboard) {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.up")
                            Text(I18n.localized("fund_export_btn", language: appState.language))
                        }
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.05))
                        .foregroundStyle(.secondary)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    // 手动粘贴导入
                    Button(action: {
                        manualPasteText = ""
                        isShowingManualPasteSheet = true
                    }) {
                        Text(I18n.localized("fund_import_manual_btn", language: appState.language))
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .underline()
                    }
                    .buttonStyle(.plain)
                }

                // 提示通知栏 (Toast)
                if let toast = toastMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.system(size: 11))
                        Text(toast)
                            .font(.system(size: 11))
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(6)
                    .transition(.opacity.combined(with: .scale))
                }

                // 搜索中状态
                if isSearching {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text(I18n.localized("fund_searching", language: appState.language))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                // 搜索结果列表
                if !searchResults.isEmpty {
                    VStack(spacing: 2) {
                        ForEach(searchResults.prefix(8)) { result in
                            let isAlreadyAdded = configStore.configs.contains(where: { $0.code == result.code })
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(result.name)
                                        .font(.system(size: 12, weight: .medium))
                                    HStack(spacing: 6) {
                                        Text(result.code)
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                        if !result.type.isEmpty {
                                            Text(result.type)
                                                .font(.system(size: 9))
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(Color.primary.opacity(0.06))
                                                .cornerRadius(3)
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                }
                                Spacer()
                                if isAlreadyAdded {
                                    Text(I18n.localized("fund_added", language: appState.language))
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                } else {
                                    Button(action: { addFund(result) }) {
                                        HStack(spacing: 3) {
                                            Image(systemName: "plus.circle.fill")
                                            Text(I18n.localized("fund_add_btn", language: appState.language))
                                        }
                                        .font(.system(size: 11, weight: .medium))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(Color.accentColor)
                                        .foregroundStyle(.white)
                                        .cornerRadius(6)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.primary.opacity(0.02))
                            .cornerRadius(6)
                        }
                    }
                    .padding(4)
                    .background(Color.primary.opacity(0.03))
                    .cornerRadius(8)
                }
            }
        }
    }

    // MARK: - Holdings Card

    private var holdingsCard: some View {
        SettingsCard(
            icon: "list.bullet.rectangle.portrait",
            iconColor: .green,
            title: I18n.localizedFormat("fund_holdings_title", language: appState.language, configStore.configs.count),
            description: I18n.localized("fund_holdings_desc", language: appState.language)
        ) {
            VStack(spacing: 10) {
                holdingsSummaryHeader

                VStack(spacing: 6) {
                    ForEach(configStore.configs) { config in
                        fundConfigRow(config: config)
                            .onDrag {
                                self.draggedConfig = config
                                return NSItemProvider(object: config.code as NSString)
                            }
                            .onDrop(of: [.text], delegate: FundDropDelegate(item: config, draggedItem: $draggedConfig))
                    }
                }
            }
        }
    }

    // MARK: - Holdings Summary Header

    private var holdingsSummaryHeader: some View {
        let totalMarketValue = configStore.configs.reduce(0.0) { sum, cfg in
            let fund = fundService.funds.first(where: { $0.code == cfg.code })
            let nav = fund?.currentNav ?? 0
            return sum + (nav * cfg.shares)
        }

        let totalCost = configStore.configs.reduce(0.0) { sum, cfg in
            guard cfg.shares > 0, cfg.costPrice > 0 else { return sum }
            return sum + (cfg.shares * cfg.costPrice)
        }

        let hasCost = totalCost > 0
        let hasShares = totalMarketValue > 0
        let totalGain = hasCost ? (totalMarketValue - totalCost) : 0.0
        let totalGainRate = hasCost ? (totalGain / totalCost * 100) : 0.0

        return HStack(spacing: 0) {
            summaryColumn(
                title: I18n.localized("fund_total_assets", language: appState.language),
                value: hasShares ? formatCurrency(totalMarketValue) : "--",
                valueColor: .primary
            )

            Divider()
                .frame(height: 22)

            summaryColumn(
                title: I18n.localized("fund_total_cost", language: appState.language),
                value: hasCost ? formatCurrency(totalCost) : "--",
                valueColor: .primary
            )

            Divider()
                .frame(height: 22)

            summaryColumn(
                title: I18n.localized("fund_total_gain", language: appState.language),
                value: hasCost ? formatSignedCurrency(totalGain) : "--",
                subValue: hasCost ? String(format: "(%@%.2f%%)", totalGainRate >= 0 ? "+" : "", totalGainRate) : nil,
                valueColor: hasCost ? gainColor(totalGain) : .secondary
            )
        }
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(8)
    }

    private func summaryColumn(title: String, value: String, subValue: String? = nil, valueColor: Color) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            HStack(spacing: 3) {
                Text(value)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(valueColor)
                if let sub = subValue {
                    Text(sub)
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(valueColor)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Fund Config Row

    private func fundConfigRow(config: FundConfig) -> some View {
        let fund = fundService.funds.first(where: { $0.code == config.code })
        let name = fund?.name ?? config.code
        let currentNav = fund?.currentNav ?? 0
        let isExpanded = expandedCode == config.code
        let hasHolding = config.shares > 0 && config.costPrice > 0
        let hasSharesOnly = config.shares > 0 && config.costPrice == 0
        let marketValue = currentNav * config.shares
        let holdingGain = hasHolding ? (currentNav - config.costPrice) * config.shares : 0.0
        let holdingGainRate = hasHolding ? (currentNav - config.costPrice) / config.costPrice * 100 : 0.0

        return VStack(spacing: 0) {
            // 常态行（单行极简）
            HStack(spacing: 8) {
                // 拖拽手柄
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .cursor(.openHand)

                // 基金名称与代码/估值
                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(config.code)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        if let gsz = fund?.estimatedValue {
                            Text("估值 \(String(format: "%.4f", gsz))")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        } else if currentNav > 0 {
                            Text("净值 \(String(format: "%.4f", currentNav))")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                Spacer()

                // 右侧持仓收益状态
                if hasHolding {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(formatSignedCurrency(holdingGain) + String(format: " (%@%.2f%%)", holdingGainRate >= 0 ? "+" : "", holdingGainRate))
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(gainColor(holdingGain))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(gainColor(holdingGain).opacity(0.12))
                            .cornerRadius(4)

                        Text("市值 " + formatCurrency(marketValue))
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                } else if hasSharesOnly {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("市值 " + formatCurrency(marketValue))
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.primary)
                        Text(I18n.localized("fund_no_cost_tip", language: appState.language))
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                    }
                } else {
                    Text(I18n.localized("fund_not_configured", language: appState.language))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.04))
                        .cornerRadius(4)
                }

                // 展开/折叠指示图标
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary.opacity(0.6))
                    .frame(width: 16, height: 16)

                // 删除按钮
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        configStore.remove(code: config.code)
                    }
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(.red.opacity(0.75))
                }
                .buttonStyle(.plain)
                .help(I18n.localized("fund_delete", language: appState.language))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    expandedCode = (expandedCode == config.code) ? nil : config.code
                }
            }

            // 展开编辑区域
            if isExpanded {
                Divider()
                    .padding(.horizontal, 10)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(I18n.localized("fund_shares", language: appState.language))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        TextField("0", value: Binding(
                            get: { config.shares },
                            set: { configStore.update(code: config.code, shares: $0, costPrice: nil) }
                        ), format: .number)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .rounded))
                        .padding(5)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(6)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(I18n.localized("fund_cost_price", language: appState.language))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        TextField("0", value: Binding(
                            get: { config.costPrice },
                            set: { configStore.update(code: config.code, shares: nil, costPrice: $0) }
                        ), format: .number)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .rounded))
                        .padding(5)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(6)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 6)
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color.primary.opacity(isExpanded ? 0.04 : 0.02))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(isExpanded ? 0.08 : 0.03), lineWidth: 1)
        )
    }

    // MARK: - General Settings Card

    private var settingsCard: some View {
        SettingsCard(
            icon: "gearshape",
            iconColor: .orange,
            title: I18n.localized("fund_settings_title", language: appState.language),
            description: I18n.localized("fund_settings_desc", language: appState.language)
        ) {
            VStack(spacing: 10) {
                // 快捷键
                HStack {
                    Text(I18n.localized("fund_shortcut", language: appState.language))
                        .font(.system(size: 12))
                    Spacer()
                    KeyboardShortcuts.Recorder(for: .toggleFundPanel)
                }

                Divider()

                // 自动刷新间隔
                HStack {
                    Text(I18n.localized("fund_settings_interval", language: appState.language))
                        .font(.system(size: 12))
                    Spacer()
                    Picker("", selection: $settings.refreshInterval) {
                        Text(I18n.localized("fund_interval_off", language: appState.language)).tag(0)
                        Text(I18n.localizedFormat("fund_interval_sec", language: appState.language, 5)).tag(5)
                        Text(I18n.localizedFormat("fund_interval_sec", language: appState.language, 10)).tag(10)
                        Text(I18n.localizedFormat("fund_interval_sec", language: appState.language, 15)).tag(15)
                        Text(I18n.localizedFormat("fund_interval_sec", language: appState.language, 30)).tag(30)
                        Text(I18n.localizedFormat("fund_interval_sec", language: appState.language, 60)).tag(60)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 100)
                }

                Divider()

                // 默认隐私模式
                HStack {
                    Text(I18n.localized("fund_settings_privacy", language: appState.language))
                        .font(.system(size: 12))
                    Spacer()
                    Toggle("", isOn: $settings.privacyMode)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }
        }
    }

    // MARK: - Manual Paste Sheet View

    private var manualPasteSheetView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(I18n.localized("fund_import_dialog_title", language: appState.language))
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Button(action: { isShowingManualPasteSheet = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Text(I18n.localized("fund_sync_desc", language: appState.language))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            TextEditor(text: $manualPasteText)
                .font(.system(size: 11, design: .monospaced))
                .frame(height: 160)
                .padding(6)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(6)

            HStack {
                Spacer()
                Button(I18n.localized("fund_cancel", language: appState.language)) {
                    isShowingManualPasteSheet = false
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)

                Button(action: {
                    if let parsed = FundConfigStore.parseConfigs(from: manualPasteText) {
                        isShowingManualPasteSheet = false
                        pendingImportConfigs = parsed
                        isShowingImportDialog = true
                    } else {
                        syncAlertMessage = I18n.localized("fund_import_clipboard_empty", language: appState.language)
                        isShowingSyncAlert = true
                    }
                }) {
                    Text(I18n.localized("fund_import_btn", language: appState.language))
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(manualPasteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 440)
    }

    // MARK: - Actions

    private func exportConfigToClipboard() {
        guard !configStore.configs.isEmpty else {
            showToast(I18n.localized("fund_export_empty_tip", language: appState.language))
            return
        }

        guard let jsonString = configStore.exportToJSONString() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(jsonString, forType: .string)
        showToast(I18n.localizedFormat("fund_export_success", language: appState.language, configStore.configs.count))
    }

    private func importConfigFromClipboard() {
        guard let clipboardText = NSPasteboard.general.string(forType: .string),
              !clipboardText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            syncAlertMessage = I18n.localized("fund_import_clipboard_empty", language: appState.language)
            isShowingSyncAlert = true
            return
        }

        if let validConfigs = FundConfigStore.parseConfigs(from: clipboardText) {
            pendingImportConfigs = validConfigs
            isShowingImportDialog = true
        } else {
            syncAlertMessage = I18n.localized("fund_import_clipboard_empty", language: appState.language)
            isShowingSyncAlert = true
        }
    }

    private func showToast(_ message: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            toastMessage = message
        }
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            withAnimation(.easeInOut(duration: 0.2)) {
                if toastMessage == message {
                    toastMessage = nil
                }
            }
        }
    }

    private func performSearch(keyword: String) {
        searchTask?.cancel()
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 1 else {
            searchResults = []
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            let results = await FundService.shared.search(keyword: trimmed)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                searchResults = results
                isSearching = false
            }
        }
    }

    private func addFund(_ result: FundSearchResult) {
        let config = FundConfig(code: result.code, shares: 0, costPrice: 0)
        configStore.add(config)
        searchText = ""
        searchResults = []
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            expandedCode = result.code
        }
        Task { await FundService.shared.refresh() }
    }

    // MARK: - Formatting Helpers

    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return "¥" + (formatter.string(from: NSNumber(value: value)) ?? "0.00")
    }

    private func formatSignedCurrency(_ value: Double) -> String {
        let sign = value > 0 ? "+" : (value < 0 ? "-" : "")
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return sign + "¥" + (formatter.string(from: NSNumber(value: abs(value))) ?? "0.00")
    }

    private func gainColor(_ value: Double) -> Color {
        if value > 0 {
            return .red
        } else if value < 0 {
            return .green
        } else {
            return .secondary
        }
    }
}

private extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        onHover { inside in
            if inside {
                cursor.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
