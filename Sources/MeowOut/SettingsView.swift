import SwiftUI
import Cocoa
import KeyboardShortcuts

struct SettingsView: View {
    @Bindable var state: AppState
    @Bindable var launchManager = LaunchManager.shared
    @Environment(\.openWindow) private var openWindow
    @State private var isAwaitingAccessibility = false
    @State private var isAwaitingAccessibilityForKeyDrop = false
    @State private var accessibilityStatus = AXIsProcessTrusted()
    @State private var history = NavigationHistory(root: SettingsRoute.tab("rest"))
    @State private var keydropBrowse = KeyDropBrowseState()
    @State private var showingRestoreDefaultsConfirmation = false

    @ObservedObject private var clamshell = ClamshellManager.shared
    @AppStorage("batteryProtectionThreshold") private var batteryProtectionThreshold = 0
    @AppStorage("showSystemMonitorCard") private var showSystemMonitorCard = true

    private var sidebarSections: [SidebarSection] {
        let hasPendingUpdate = UpdateChecker.shared.hasPendingUpdate
        let lang = state.language
        return [
            SidebarSection(id: "health", title: I18n.localized("settings_group_health", language: lang), items: [
                SidebarItem(id: "rest", title: I18n.localized("settings_tab_health", language: lang), icon: "heart.text.square", iconColor: .pink),
                SidebarItem(id: "behavior", title: I18n.localized("settings_section_behavior", language: lang), icon: "cat.circle", iconColor: .orange),
            ]),
            SidebarSection(id: "tools", title: I18n.localized("settings_group_tools", language: lang), items: [
                SidebarItem(id: "keydrop", title: I18n.localized("settings_tab_keydrop", language: lang), icon: "keyboard", iconColor: .indigo),
                SidebarItem(id: "clipboard", title: I18n.localized("settings_tab_clipboard", language: lang), icon: "clipboard", iconColor: .green),
                SidebarItem(id: "shelf", title: I18n.localized("settings_tab_shelf", language: lang), icon: "tray.and.arrow.down", iconColor: .cyan),
                SidebarItem(id: "quick_actions", title: I18n.localized("menu_quick_actions", language: lang), icon: "bolt.fill", iconColor: .yellow),
            ]),
            SidebarSection(id: "data", title: I18n.localized("settings_group_data", language: lang), items: [
                SidebarItem(id: "fund", title: I18n.localized("settings_tab_fund", language: lang), icon: "chart.line.uptrend.xyaxis", iconColor: .red),
                SidebarItem(id: "memos", title: I18n.localized("settings_tab_memos", language: lang), icon: "note.text", iconColor: .purple),
            ]),
            SidebarSection(id: "system", title: I18n.localized("settings_group_system", language: lang), items: [
                SidebarItem(id: "general", title: I18n.localized("settings_tab_general", language: lang), icon: "gearshape", iconColor: Color(nsColor: .systemGray)),
                SidebarItem(id: "power", title: I18n.localized("settings_tab_power", language: lang), icon: "bolt.circle", iconColor: .teal),
                SidebarItem(id: "permissions", title: I18n.localized("settings_tab_permissions", language: lang), icon: "lock.shield", iconColor: .blue),
                SidebarItem(id: "about", title: I18n.localized("settings_subtab_about", language: lang), icon: "info.circle", iconColor: .brown, hasBadge: hasPendingUpdate),
            ]),
        ]
    }

    var body: some View {
        // 侧栏刻意常驻，不允许折叠；正因为固定成 .all，SwiftUI 自动注入的侧栏开关点了也不生效，
        // 才需要下面 .toolbar(removing: .sidebarToggle) 把它摘掉，别当成死代码删。
        NavigationSplitView(columnVisibility: .constant(.all)) {
            SidebarList(sections: sidebarSections, selection: sidebarSelection)
        } detail: {
            // 常用语的两个页面自带滚动区与自适应高度的编辑器，套在外层 ScrollView 里会拿到
            // 无界高度建议，导致内层列表不再滚动、值行塌成一条。只有卡片式设置页需要外层滚动。
            switch history.current {
            case .keydropManager, .keydropManagerEntry:
                detailPane
            case .tab, .statistics:
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        detailPane
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .navigationTitle(currentPageTitle)
        .toolbar(removing: .sidebarToggle)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    history.goBack()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(!history.canGoBack)
                .keyboardShortcut("[", modifiers: .command)
                .help(I18n.localized("settings_nav_back", language: state.language))
                .accessibilityLabel(I18n.localized("settings_nav_back", language: state.language))

                Button {
                    history.goForward()
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(!history.canGoForward)
                .keyboardShortcut("]", modifiers: .command)
                .help(I18n.localized("settings_nav_forward", language: state.language))
                .accessibilityLabel(I18n.localized("settings_nav_forward", language: state.language))
            }
        }
        .frame(minWidth: 620, idealWidth: 660, minHeight: 560, idealHeight: 580)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willBecomeActiveNotification)) { _ in
            let trusted = AXIsProcessTrusted()
            accessibilityStatus = trusted
            if trusted {
                if isAwaitingAccessibility {
                    state.enableGlobalKeyboardScold = true
                    isAwaitingAccessibility = false
                }
                if isAwaitingAccessibilityForKeyDrop {
                    state.keyDropEnabled = true
                    isAwaitingAccessibilityForKeyDrop = false
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SwitchToPermissionsTab"))) { _ in
            history.push(.tab("permissions"))
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenFundSettings"))) { _ in
            history.push(.tab("fund"))
        }
        .onAppear {
            clamshell.syncWithSystem()
            applyPendingNavigationTarget()
        }
        .onChange(of: state.settingsNavigationTarget) { _, _ in
            applyPendingNavigationTarget()
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        switch history.current {
        case .keydropManager:
            SnippetManagerListView(browse: keydropBrowse) { id in
                history.push(.keydropManagerEntry(id))
            }
        case .keydropManagerEntry(let id):
            // 按 id 绑定身份，保证编辑页的本地 @State 每条一份。今天路由切换本身就会拆掉旧视图，
            // 所以这层 .id 只是低成本的防御，防止将来视图被复用后状态串到下一条。
            SnippetEntryEditorView(entryID: id)
                .id(id)
        case .statistics:
            StatsView(state: state)
        case .tab(let id):
            switch id {
            case "behavior": behaviorCards
            case "keydrop": keyDropCards
            case "clipboard": ClipboardSettingsView()
            case "shelf": ShelfSettingsView()
            case "quick_actions": QuickActionsSettingsView(state: state)
            case "fund": FundSettingsView()
            case "memos": MemosSettingsView(state: state)
            case "permissions": permissionsCards
            case "general": generalCards
            case "power": powerCards
            case "about": aboutCards
            default: restCards
            }
        }
    }

    /// 工具栏标题跟随当前路由：钻进子页时显示该页自己的名字，与 macOS 系统设置的钻取体验一致。
    private var currentPageTitle: String {
        switch history.current {
        case .keydropManager, .keydropManagerEntry:
            return I18n.localized("keydrop_manager_title", language: state.language)
        case .statistics:
            return I18n.localized("stats_page_title", language: state.language)
        case .tab(let id):
            return sidebarSections.flatMap(\.items).first { $0.id == id }?.title
                ?? I18n.localized("settings_window_title", language: state.language)
        }
    }

    /// 侧栏选中与导航历史的双向映射。
    /// 读方向由当前路由推导；写方向里「点回已高亮的父页签」要能退出子页，其余重复点击不产生历史。
    private var sidebarSelection: Binding<String?> {
        Binding(
            get: { history.current.highlightedSidebarID },
            set: { newValue in
                guard let id = newValue else { return }   // List 允许点空白清空选中，这里不接受
                switch history.current {
                case .tab(let currentID) where currentID == id:
                    return                                // 已停在该页根，无操作
                default:
                    history.push(.tab(id))                // 含「从管理器退回常用语页根」
                }
            }
        )
    }

    private func applyPendingNavigationTarget() {
        switch state.settingsNavigationTarget {
        case .update:
            history.push(.tab("about"))
            state.settingsNavigationTarget = nil
        case .permissions:
            history.push(.tab("permissions"))
            state.settingsNavigationTarget = nil
        case .memos:
            history.push(.tab("memos"))
            state.settingsNavigationTarget = nil
        case .fund:
            history.push(.tab("fund"))
            state.settingsNavigationTarget = nil
        case .statistics:
            // 设置窗口常驻复用，用户关窗时可能正停在统计页，此时 push(.tab("rest")) 不是空操作，
            // 会在历史里压出 [.., rest, statistics, rest, statistics]，返回键第二次会又回到刚离开的页
            guard history.current != .statistics else {
                state.settingsNavigationTarget = nil
                return
            }
            // 推两层，让返回键的行为与用户从健康作息页手动进入时一致
            history.push(.tab("rest"))
            history.push(.statistics)
            state.settingsNavigationTarget = nil
        case nil:
            break
        }
    }

    @ViewBuilder
    private var restCards: some View {
        VStack(spacing: 20) {
        // 分组 1：工时休息（首分组不带标题，与其他 tab 一致）
        SettingsGroup {
            SettingsRow(I18n.localized("rest_reminder_enabled", language: state.language),
                        description: I18n.localized("rest_reminder_enabled_desc", language: state.language)) {
                Toggle("", isOn: $state.enableRestReminder)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            Group {
                SettingsRowDivider()
                SettingsRow(I18n.localized("rest_pet_animation_enabled", language: state.language),
                            description: I18n.localized("rest_pet_animation_enabled_desc", language: state.language)) {
                    Toggle("", isOn: $state.enableTrayPetAnimation)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                SettingsRowDivider()
                PresetValueRow(title: I18n.localized("settings_work_duration", language: state.language),
                               description: I18n.localized("settings_work_duration_desc", language: state.language),
                               value: $state.workDurationMinutes,
                               preset: .workDuration,
                               unitKey: "unit_minutes_short",
                               language: state.language)
                SettingsRowDivider()
                PresetValueRow(title: I18n.localized("settings_rest_duration", language: state.language),
                               description: I18n.localized("settings_rest_duration_desc", language: state.language),
                               value: $state.restDurationMinutes,
                               preset: .restDuration,
                               unitKey: "unit_minutes_short",
                               language: state.language)
                SettingsRowDivider()
                PresetValueRow(title: I18n.localized("settings_alert_notice", language: state.language),
                               description: I18n.localized("settings_alert_notice_desc", language: state.language),
                               value: $state.alertBeforeRestMinutes,
                               preset: .alertBefore,
                               unitKey: "unit_minutes_short",
                               language: state.language)
                SettingsRowDivider()
                PresetValueRow(title: I18n.localized("settings_rest_to_reset", language: state.language),
                               description: I18n.localized("settings_rest_to_reset_desc", language: state.language),
                               value: $state.restToResetMinutes,
                               preset: .restToReset,
                               unitKey: "unit_minutes_short",
                               language: state.language)
            }
            .disabled(!state.enableRestReminder)
            .opacity(state.enableRestReminder ? 1.0 : 0.5)
        }

        // 分组 2：喝水提醒
        SettingsGroup(I18n.localized("settings_subtab_water", language: state.language)) {
            SettingsRow(I18n.localized("water_settings_enabled", language: state.language)) {
                Toggle("", isOn: $state.waterReminderEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            Group {
                SettingsRowDivider()
                SettingsRow(I18n.localized("water_settings_mode", language: state.language)) {
                    Picker("", selection: $state.waterReminderMode) {
                        Text(I18n.localized("water_settings_mode_rhythm", language: state.language)).tag(AppState.WaterReminderMode.followRhythm)
                        Text(I18n.localized("water_settings_mode_custom", language: state.language)).tag(AppState.WaterReminderMode.custom)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }

                if state.waterReminderMode == .custom {
                    SettingsRowDivider()
                    PresetValueRow(title: I18n.localized("water_settings_interval", language: state.language),
                                   value: $state.waterCustomInterval,
                                   preset: .waterInterval,
                                   unitKey: "unit_minutes_short",
                                   language: state.language)
                }
            }
            .disabled(!state.waterReminderEnabled)
            .opacity(state.waterReminderEnabled ? 1.0 : 0.5)
        }
        .disabled(!state.enableRestReminder)
        .opacity(state.enableRestReminder ? 1.0 : 0.5)

        // 分组 3：每日目标
        SettingsGroup(I18n.localized("settings_subtab_daily_goals", language: state.language)) {
            PresetValueRow(title: I18n.localized("stats_todays_goal", language: state.language),
                           value: $state.dailyWorkGoal,
                           preset: .dailyWorkGoal,
                           unitKey: "unit_hours",
                           language: state.language)
            SettingsRowDivider()
            PresetValueRow(title: I18n.localized("water_settings_goal", language: state.language),
                           value: $state.dailyWaterGoal,
                           preset: .dailyWaterGoal,
                           unitKey: "unit_cups",
                           language: state.language)
        }

        // 分组 4：统计入口（统计是推进出去的独立页，不受本页「恢复默认」影响）
        SettingsGroup {
            SettingsRow(I18n.localized("stats_settings_entry_title", language: state.language),
                        description: I18n.localized("stats_settings_entry_desc", language: state.language)) {
                Button(action: { history.push(.statistics) }) {
                    Text(I18n.localized("stats_settings_entry_btn", language: state.language))
                }
            }
        }

        // 页面级重置：作用于本页全部设置（工时休息 + 喝水提醒 + 每日目标）
        HStack {
            Button(action: { showingRestoreDefaultsConfirmation = true }) {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 11, weight: .semibold))
                    Text(I18n.localized("settings_restore_defaults", language: state.language))
                        .font(.system(size: 12))
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(I18n.localized("settings_restore_defaults", language: state.language))
            Spacer()
        }
        .padding(.horizontal, 12)
        }
        .animation(.easeInOut(duration: 0.2), value: state.enableRestReminder)
        .alert(I18n.localized("settings_restore_defaults_confirm_title", language: state.language),
               isPresented: $showingRestoreDefaultsConfirmation) {
            Button(I18n.localized("keydrop_cancel_btn", language: state.language), role: .cancel) { }
            Button(I18n.localized("settings_restore_defaults", language: state.language), role: .destructive) {
                state.resetIntervalsToDefaults()
            }
        } message: {
            Text(I18n.localized("settings_restore_defaults_confirm_message", language: state.language))
        }
    }

    @ViewBuilder
    private var behaviorCards: some View {
        // 分组 1：宠物
        SettingsGroup(I18n.localized("settings_subtab_pet", language: state.language)) {
            petSelectionGrid
                .padding(12)
        }

        // 分组 2：性格
        SettingsGroup(I18n.localized("settings_subtab_personality", language: state.language)) {
            SettingsRow(I18n.localized("settings_personality", language: state.language),
                        description: I18n.localized("settings_personality_desc", language: state.language)) {
                Picker("", selection: $state.selectedPersonality) {
                    Text(I18n.localized("settings_personality_gentle", language: state.language)).tag(PetPersonality.gentle)
                    Text(I18n.localized("settings_personality_strict", language: state.language)).tag(PetPersonality.strict)
                    Text(I18n.localized("settings_personality_tsundere", language: state.language)).tag(PetPersonality.tsundere)
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
        }

        // 分组 3：交互
        SettingsGroup(I18n.localized("settings_subtab_interactions", language: state.language)) {
            SettingsRow(I18n.localized("settings_cursor_chasing", language: state.language),
                        description: I18n.localized("settings_cursor_chasing_desc", language: state.language)) {
                Toggle("", isOn: $state.enableCursorChasing)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            SettingsRowDivider()
            SettingsRow(I18n.localized("settings_global_scold", language: state.language),
                        description: I18n.localized("settings_global_scold_desc", language: state.language)) {
                Toggle("", isOn: globalScoldBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            SettingsRowDivider()
            SettingsRow(I18n.localized("settings_preview_title", language: state.language),
                        description: I18n.localizedFormat("settings_preview_desc", language: state.language, I18n.localized(state.selectedPet.localizationKey, language: state.language))) {
                previewButtons
            }
        }
    }

    @ViewBuilder
    private var generalCards: some View {
        SettingsGroup {
            SettingsRow(I18n.localized("settings_language", language: state.language)) {
                Picker("", selection: $state.language) {
                    ForEach(AppState.AppLanguage.allCases) { lang in
                        Text(lang.displayName(currentLanguage: state.language)).tag(lang)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            SettingsRowDivider()
            SettingsRow(I18n.localized("settings_appearance", language: state.language)) {
                Picker("", selection: $state.appearanceMode) {
                    ForEach(AppState.AppearanceMode.allCases) { mode in
                        Text(mode.displayName(currentLanguage: state.language)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            SettingsRowDivider()
            SettingsRow(I18n.localized("settings_launch_at_login", language: state.language),
                        description: I18n.localized("settings_launch_at_login_desc", language: state.language)) {
                Toggle("", isOn: Binding(
                    get: { launchManager.isLaunchAtLoginEnabled },
                    set: { launchManager.toggleLaunchAtLogin(enabled: $0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }
            SettingsRowDivider()
            SettingsRow(I18n.localized("settings_classic_tray_icon", language: state.language),
                        description: I18n.localized("settings_classic_tray_icon_desc", language: state.language)) {
                Toggle("", isOn: $state.useClassicTrayIcon)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            SettingsRowDivider()
            SettingsRow(I18n.localized("settings_system_monitor_card_title", language: state.language),
                        description: I18n.localized("settings_system_monitor_card_desc", language: state.language)) {
                Toggle("", isOn: $showSystemMonitorCard)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }
        // 语言切换时整组重建：segmented Picker 桥接 NSSegmentedControl，
        // 标签变短时段宽不收缩，会把行布局卡坏、挤掉行标题（如 en → 跟随系统）
        .id(state.language)
    }

    @ViewBuilder
    private var powerCards: some View {
        SettingsGroup {
            SettingsRow(I18n.localized("power_clamshell_title", language: state.language),
                        description: I18n.localized("power_clamshell_desc", language: state.language)) {
                Toggle("", isOn: Binding(
                    get: { clamshell.isEnabledGlobally },
                    set: { newValue in
                        if !SudoersManager.isConfigured() {
                            showSudoersNSAlert(pendingValue: newValue)
                        } else {
                            clamshell.setClamshellMode(enabled: newValue)
                        }
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }

            if clamshell.isExternallyEnabled {
                SettingsRowDivider()
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.orange)
                        .font(.system(size: 11))
                    Text(I18n.localized("power_clamshell_external_tip", language: state.language))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
            }

            SettingsRowDivider()
            PresetValueRow(title: I18n.localized("power_battery_title", language: state.language),
                           description: I18n.localized("power_battery_desc", language: state.language),
                           value: $batteryProtectionThreshold,
                           preset: .batteryThreshold,
                           unitKey: "unit_percent",
                           zeroLabelKey: "power_battery_off",
                           language: state.language)
        }
    }

    @ViewBuilder
    private var aboutCards: some View {
        VStack(spacing: 8) {
            if let appIcon = NSImage(named: "AppIcon") {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            Text("MeowOut")
                .font(.title2)
                .bold()
            Text("\(I18n.localizedFormat("settings_version", language: state.language, Bundle.main.appVersion)) (\(currentGitCommit))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(I18n.localized("settings_about_description", language: state.language))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)

        SettingsGroup(I18n.localized("settings_check_updates", language: state.language)) {
            updateContent
                .padding(12)
        }
    }

    @ViewBuilder
    private var updateContent: some View {
        let checker = UpdateChecker.shared
        VStack(alignment: .leading, spacing: 12) {
            if let lastChecked = checker.lastCheckedAt {
                Text(I18n.localizedFormat("settings_update_last_checked", language: state.language, lastCheckedFormatter.string(from: lastChecked)))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            switch checker.status {
                case .checking:
                    HStack {
                        ProgressView().controlSize(.small)
                        Text(I18n.localized("settings_update_checking", language: state.language))
                            .font(.caption)
                    }
                case .downloading(let progress):
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: progress)
                            .tint(.blue)
                        Text(I18n.localizedFormat("settings_update_downloading", language: state.language, Int64(progress * 100)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                case .available(let version, let notes, _):
                    VStack(alignment: .leading, spacing: 8) {
                        Text(I18n.localizedFormat("settings_update_available", language: state.language, version))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.blue)
                        
                        if !notes.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                ScrollView {
                                    MarkdownReleaseNotesView(text: notes)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .frame(maxHeight: 140)
                            }
                            .padding(10)
                            .background(Color.secondary.opacity(0.06))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                            )
                        }

                        Button(action: {
                            Task { await checker.downloadAndInstall(language: state.language) }
                        }) {
                            Text(I18n.localized("settings_update_download_install", language: state.language))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(Color.blue)
                                .cornerRadius(8)
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                    }
                case .readyToInstall(let version, _):
                    VStack(alignment: .leading, spacing: 8) {
                        Button(action: {
                            Task { await checker.downloadAndInstall(language: state.language) } // Re-triggers install logic
                        }) {
                            Text("v\(version) \(I18n.localized("settings_update_download_install", language: state.language))")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(Color.green)
                                .cornerRadius(8)
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                    }
                case .idle:
                    HStack {
                        if checker.lastCheckedAt != nil {
                            Text(I18n.localized("settings_update_up_to_date", language: state.language))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        checkButton
                    }
                case .error(let error):
                    HStack {
                        Text(error.localizedDescription(language: state.language))
                            .font(.caption)
                            .foregroundStyle(.red)
                        Spacer()
                        checkButton
                    }
                }
        }
    }

    private var lastCheckedFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }

    private func showSudoersNSAlert(pendingValue: Bool) {
        let alert = NSAlert()
        alert.messageText = I18n.localized("power_clamshell_alert_title", language: state.language)
        alert.informativeText = I18n.localized("power_clamshell_alert_msg", language: state.language)
        alert.addButton(withTitle: I18n.localized("power_clamshell_alert_auth", language: state.language))
        alert.addButton(withTitle: I18n.localized("power_clamshell_alert_cancel", language: state.language))
        
        if alert.runModal() == .alertFirstButtonReturn {
            SudoersManager.install { success in
                if success {
                    clamshell.setClamshellMode(enabled: pendingValue)
                }
            }
        }
    }

    @ViewBuilder
    private var checkButton: some View {
        Button(action: {
            Task { await UpdateChecker.shared.check() }
        }) {
            Text(I18n.localized("settings_check_updates", language: state.language))
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var petSelectionGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 70, maximum: 70), spacing: 16)],
            alignment: .leading,
            spacing: 16
        ) {
            ForEach(AppState.PetType.allCases) { pet in
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        state.selectedPet = pet
                    }
                } label: {
                    VStack {
                        ZStack(alignment: .top) {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(state.selectedPet == pet ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))
                                .frame(width: 70, height: 70)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(state.selectedPet == pet ? Color.accentColor : Color.clear, lineWidth: 2)
                                )

                            Group {
                                switch pet {
                                case .clawd: ClawdView(pose: .rest, height: 36)
                                case .panda: PandaView(pose: .rest, height: 36)
                                case .pika: PikaView(pose: .rest, height: 36)
                                }
                            }
                            .padding(.top, 12)
                        }

                        Text(I18n.localized(pet.localizationKey, language: state.language))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(state.selectedPet == pet ? .primary : .secondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(I18n.localized(pet.localizationKey, language: state.language))
                .accessibilityAddTraits(state.selectedPet == pet ? .isSelected : [])
            }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 2)
    }

    private var globalScoldBinding: Binding<Bool> {
        Binding(
            get: { state.enableGlobalKeyboardScold && accessibilityStatus },
            set: { newValue in
                if newValue {
                    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                    let trusted = AXIsProcessTrustedWithOptions(options)
                    accessibilityStatus = trusted
                    if trusted {
                        state.enableGlobalKeyboardScold = true
                        isAwaitingAccessibility = false
                    } else {
                        state.enableGlobalKeyboardScold = false
                        isAwaitingAccessibility = true
                        history.push(.tab("permissions"))
                    }
                } else {
                    state.enableGlobalKeyboardScold = false
                    isAwaitingAccessibility = false
                }
            }
        )
    }

    private var keyDropBinding: Binding<Bool> {
        Binding(
            get: { state.keyDropEnabled && accessibilityStatus },
            set: { newValue in
                if newValue {
                    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                    let trusted = AXIsProcessTrustedWithOptions(options)
                    accessibilityStatus = trusted
                    if trusted {
                        state.keyDropEnabled = true
                        isAwaitingAccessibilityForKeyDrop = false
                    } else {
                        state.keyDropEnabled = false
                        isAwaitingAccessibilityForKeyDrop = true
                        history.push(.tab("permissions"))
                    }
                } else {
                    state.keyDropEnabled = false
                    isAwaitingAccessibilityForKeyDrop = false
                }
            }
        )
    }

    @ViewBuilder
    private var keyDropCards: some View {
        SettingsGroup {
            SettingsRow(I18n.localized("keydrop_enabled", language: state.language),
                        description: I18n.localized("keydrop_enabled_desc", language: state.language)) {
                Toggle("", isOn: keyDropBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            SettingsRowDivider()
            SettingsRow(I18n.localized("keydrop_shortcut", language: state.language),
                        description: I18n.localized("keydrop_shortcut_desc", language: state.language)) {
                KeyboardShortcuts.Recorder(for: .togglePanel)
            }
            SettingsRowDivider()
            SettingsRow(I18n.localized("keydrop_manage_title", language: state.language),
                        description: I18n.localized("keydrop_manage_desc", language: state.language)) {
                Button(action: {
                    history.push(.keydropManager)
                }) {
                    Text(I18n.localized("keydrop_open_manager_btn", language: state.language))
                }
            }
        }
    }

    @ViewBuilder
    private var permissionsCards: some View {
        SettingsGroup {
            SettingsRow(I18n.localized("accessibility_card_title", language: state.language),
                        description: I18n.localized("accessibility_card_desc", language: state.language)) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(accessibilityStatus ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(accessibilityStatus
                         ? I18n.localized("accessibility_status_granted", language: state.language)
                         : I18n.localized("accessibility_status_denied", language: state.language))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(accessibilityStatus ? .green : .red)
                }
            }

            if !accessibilityStatus {
                SettingsRowDivider()
                Button(action: {
                    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                    _ = AXIsProcessTrustedWithOptions(options)
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    Text(I18n.localized("accessibility_auth_btn", language: state.language))
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
            }
        }
    }

    @ViewBuilder
    private var previewButtons: some View {
        HStack(spacing: 8) {
            if state.isPreviewing {
                Button(action: {
                    CatOverlayController.shared.stopPreview()
                }) {
                    Text(I18n.localized("settings_preview_stop", language: state.language))
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            } else {
                Button(action: {
                    CatOverlayController.shared.previewAlerting()
                }) {
                    Text(I18n.localized("settings_preview_alerting", language: state.language))
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.accentColor.opacity(0.1))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)

                Button(action: {
                    CatOverlayController.shared.previewResting()
                }) {
                    Text(I18n.localized("settings_preview_resting", language: state.language))
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.accentColor.opacity(0.1))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct MarkdownReleaseNotesView: View {
    let text: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(text.components(separatedBy: .newlines).enumerated()), id: \.offset) { _, line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    EmptyView()
                } else if trimmed.hasPrefix("### ") {
                    Text(LocalizedStringKey(String(trimmed.dropFirst(4))))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.primary)
                        .padding(.top, 4)
                } else if trimmed.hasPrefix("## ") {
                    Text(LocalizedStringKey(String(trimmed.dropFirst(3))))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.primary)
                        .padding(.top, 6)
                } else if trimmed.hasPrefix("# ") {
                    Text(LocalizedStringKey(String(trimmed.dropFirst(2))))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.primary)
                        .padding(.top, 8)
                } else if trimmed.hasPrefix("- ") {
                    HStack(alignment: .top, spacing: 4) {
                        Text("•")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(LocalizedStringKey(String(trimmed.dropFirst(2))))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                } else if trimmed.hasPrefix("* ") && !trimmed.hasSuffix(" *") {
                    HStack(alignment: .top, spacing: 4) {
                        Text("•")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(LocalizedStringKey(String(trimmed.dropFirst(2))))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(LocalizedStringKey(trimmed))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                }
            }
        }
    }
}

struct QuickActionsSettingsView: View {
    @Bindable var state: AppState

    var body: some View {
        VStack(spacing: 20) {
            SettingsGroup {
                SettingsRow(I18n.localized("quick_tools_enabled", language: state.language),
                            description: I18n.localized("quick_tools_enabled_desc", language: state.language)) {
                    Toggle("", isOn: $state.showQuickToolsCard)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }

            SettingsGroup(I18n.localized("menu_quick_actions", language: state.language)) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(I18n.localized("quick_actions_settings_desc", language: state.language))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    QuickActionsListEditor(state: state)
                }
                .padding(12)
            }
            .disabled(!state.showQuickToolsCard)
            .opacity(state.showQuickToolsCard ? 1.0 : 0.5)

            SettingsGroup(I18n.localized("launcher_settings_title", language: state.language)) {
                LauncherTriggerSettingsView(state: state)
                    .padding(12)
            }

            if state.launcherEnabled {
                SettingsGroup(I18n.localized("launcher_ring_editor_title", language: state.language)) {
                    LauncherRingsEditorView(state: state)
                        .padding(12)
                }
            }
        }
    }
}

struct QuickActionsListEditor: View {
    @Bindable var state: AppState
    @State private var showingBuiltInOptions = false
    
    var body: some View {
        VStack(alignment: .leading) {
            List {
                ForEach(Array(state.quickTools.enumerated()), id: \.element.id) { index, tool in
                    HStack {
                        if case .builtIn(let type) = tool {
                            Text("\(type.icon) \(type.localizedName(language: state.language))")
                        } else if case .appShortcut(_, let name, let path, _) = tool {
                            HStack(spacing: 8) {
                                AppIconView(path: path)
                                Text(name)
                            }
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            state.quickTools.remove(at: index)
                        }) {
                            Image(systemName: "minus.circle.fill")
                                .foregroundColor(.red.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 4)
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(index == 1 ? Color.primary.opacity(0.05) : Color.clear)
                }
                .onMove(perform: moveTool)
                .onDelete(perform: deleteTool)
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .frame(minHeight: 150)

            HStack {
                Button(action: addExternalApp) {
                    Label(I18n.localized("quick_actions_add_app", language: state.language), systemImage: "plus.app")
                }
                Button(action: { showingBuiltInOptions = true }) {
                    Label(I18n.localized("quick_actions_add_builtin", language: state.language), systemImage: "plus.square.fill")
                }
                .popover(isPresented: $showingBuiltInOptions) {
                    VStack(spacing: 8) {
                        Button(I18n.localized("menu_keep_awake", language: state.language)) { addBuiltIn(.keepAwake) }
                        Button(I18n.localized("menu_keyboard_cleaning", language: state.language)) { addBuiltIn(.keyboardCleaning) }
                        Button(I18n.localized("menu_screen_cleaning", language: state.language)) { addBuiltIn(.screenCleaning) }
                        Button(I18n.localized("memos_settings_quick_capture_short", language: state.language)) { addBuiltIn(.memosQuickCapture) }
                        Button(I18n.localized("memos_action_open_memos", language: state.language)) { addBuiltIn(.memosOpenBrowser) }
                        Button(I18n.localized("menu_breathing", language: state.language)) { addBuiltIn(.breathing) }
                        Button(I18n.localized("menu_toolbox_2fa", language: state.language)) { addBuiltIn(.toolbox2FA) }
                    }.padding()
                }
            }
            .padding(.top, 4)
        }
    }

    private func moveTool(from source: IndexSet, to destination: Int) {
        state.quickTools.move(fromOffsets: source, toOffset: destination)
    }

    private func deleteTool(at offsets: IndexSet) {
        state.quickTools.remove(atOffsets: offsets)
    }

    private func addBuiltIn(_ type: BuiltInToolType) {
        if !state.quickTools.contains(.builtIn(type)) {
            state.quickTools.append(.builtIn(type))
        }
        showingBuiltInOptions = false
    }

    private func addExternalApp() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                let name = url.deletingPathExtension().lastPathComponent
                let path = url.path
                let bookmarkData = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                
                let newTool = QuickTool.appShortcut(id: UUID(), name: name, path: path, bookmarkData: bookmarkData)
                state.quickTools.append(newTool)
            }
        }
    }
}

struct LauncherTriggerSettingsView: View {
    @Bindable var state: AppState
    @State private var isAccessibilityTrusted = AXIsProcessTrusted()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(I18n.localized("launcher_trigger_enable", language: state.language), isOn: $state.launcherEnabled)
                .toggleStyle(.switch)
            
            if state.launcherEnabled {
                
                Divider().padding(.vertical, 4)
                
                Picker("", selection: $state.launcherTriggerMode) {
                    Text(I18n.localized("launcher_trigger_mode_shortcut", language: state.language))
                        .tag(AppState.LauncherTriggerMode.keyboardShortcut)
                    Text(I18n.localized("launcher_trigger_mode_advanced", language: state.language))
                        .tag(AppState.LauncherTriggerMode.advancedModifier)
                }
                .pickerStyle(.segmented)

                if state.launcherTriggerMode == .advancedModifier {
                    advancedModifierSettings
                } else {
                    HStack {
                        Text(I18n.localized("launcher_trigger_key", language: state.language))
                            .font(.system(size: 12))
                        Spacer()
                        KeyboardShortcuts.Recorder(for: .toggleLauncher)
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willBecomeActiveNotification)) { _ in
            isAccessibilityTrusted = AXIsProcessTrusted()
        }
    }

    @ViewBuilder
    private var advancedModifierSettings: some View {
        if !isAccessibilityTrusted {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text(I18n.localized("launcher_requires_accessibility_tip", language: state.language))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: {
                    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                    _ = AXIsProcessTrustedWithOptions(options)
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    Text(I18n.localized("accessibility_auth_btn", language: state.language))
                        .font(.system(size: 11, weight: .semibold))
                }
            }
            .padding(8)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(6)
        }

        HStack {
            Text(I18n.localized("launcher_trigger_key", language: state.language))
                .font(.system(size: 12))
            Spacer()
            Picker("", selection: $state.launcherTriggerKey) {
                ForEach(AppState.LauncherTriggerModifier.allCases) { modifier in
                    Text(modifier.displayName).tag(modifier)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 140)
        }

        Toggle(isOn: $state.launcherDoubleClickToActivate) {
            VStack(alignment: .leading, spacing: 2) {
                Text(I18n.localized("launcher_trigger_double_click", language: state.language))
                    .font(.system(size: 12))
                Text(I18n.localized("launcher_trigger_double_click_desc", language: state.language))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .toggleStyle(.switch)

        Toggle(isOn: $state.launcherClickToLaunch) {
            VStack(alignment: .leading, spacing: 2) {
                Text(I18n.localized("launcher_click_to_launch", language: state.language))
                    .font(.system(size: 12))
                Text(I18n.localized("launcher_click_to_launch_desc", language: state.language))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .toggleStyle(.switch)

        VStack(alignment: .trailing, spacing: 4) {
            HStack {
                Text(I18n.localized("launcher_long_press_delay", language: state.language))
                    .font(.system(size: 12))
                Spacer()
                Text(String(format: "%.2fs", state.launcherLongPressDelay))
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.orange)
            }
            Slider(value: $state.launcherLongPressDelay, in: 0.05...2.00, step: 0.05)
        }
    }
}

struct LauncherRingsEditorView: View {
    @Bindable var state: AppState
    
    @State private var selectedRingId: UUID? = nil
    @State private var showingAddActionPopover = false
    @State private var isEditingName = false
    @State private var newRingName = ""
    
    private var currentSelectedRingId: UUID? {
        selectedRingId ?? state.launcherRings.first?.id
    }
    
    var body: some View {
        VStack(spacing: 12) {
            Text(I18n.localized("launcher_scroll_switch_tip", language: state.language))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Ring Tab List
            HStack {
                ForEach(state.launcherRings) { ring in
                    Button(action: {
                        selectedRingId = ring.id
                    }) {
                        Text(ring.name)
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(currentSelectedRingId == ring.id ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05))
                            .cornerRadius(6)
                            .foregroundColor(currentSelectedRingId == ring.id ? .accentColor : .primary)
                    }
                    .buttonStyle(.plain)
                }
                
                Button(action: {
                    addNewRing()
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(6)
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                
                Spacer()
            }
            .onAppear {
                if selectedRingId == nil, let first = state.launcherRings.first {
                    selectedRingId = first.id
                }
            }
            
            if let activeId = currentSelectedRingId,
               let activeRing = state.launcherRings.first(where: { $0.id == activeId }) {
                VStack(spacing: 12) {
                    // Editable Name
                    HStack(spacing: 8) {
                        if isEditingName {
                            TextField(I18n.localized("launcher_rename_ring_placeholder", language: state.language), text: $newRingName, onCommit: {
                                if !newRingName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    renameRing(id: activeRing.id, to: newRingName)
                                }
                                isEditingName = false
                            })
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 150)
                            
                            Button(I18n.localized("memos_action_save", language: state.language)) {
                                if !newRingName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    renameRing(id: activeRing.id, to: newRingName)
                                }
                                isEditingName = false
                            }
                            .buttonStyle(.borderedProminent)
                        } else {
                            Text(activeRing.name)
                                .font(.system(size: 13, weight: .bold))
                            
                            Button(action: {
                                newRingName = activeRing.name
                                isEditingName = true
                            }) {
                                Image(systemName: "pencil")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 10))
                            }
                            .buttonStyle(.plain)
                        }
                        
                        Spacer()
                    }
                    .padding(.top, 4)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        if activeRing.tools.isEmpty {
                            Text(I18n.localized("launcher_ring_actions_empty", language: state.language))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 12)
                        } else {
                            List {
                                ForEach(Array(activeRing.tools.enumerated()), id: \.offset) { index, tool in
                                    HStack(spacing: 8) {
                                        Text("\(index + 1)")
                                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                                            .foregroundColor(.secondary)
                                            .frame(width: 18)
                                        
                                        if case .builtIn(let type) = tool {
                                            Text(type.icon)
                                            Text(type.localizedName(language: state.language))
                                        } else if case .appShortcut(_, let name, let path, _) = tool {
                                            AppIconView(path: path)
                                            Text(name)
                                        }
                                        
                                        Spacer()
                                        
                                        Button(action: {
                                            removeTool(from: activeRing.id, at: index)
                                        }) {
                                            Image(systemName: "minus.circle.fill")
                                                .foregroundColor(.red.opacity(0.8))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.vertical, 4)
                                }
                                .onMove { source, destination in
                                    moveTool(in: activeRing.id, from: source, to: destination)
                                }
                            }
                            .listStyle(.inset(alternatesRowBackgrounds: true))
                            .frame(minHeight: 120)
                        }
                        
                        HStack {
                            Button(action: {
                                showingAddActionPopover = true
                            }) {
                                Label(I18n.localized("launcher_ring_add_action", language: state.language), systemImage: "plus.circle")
                            }
                            .disabled(activeRing.tools.count >= LauncherRing.maxTools)
                            .popover(isPresented: $showingAddActionPopover) {
                                popoverToolList(for: activeRing.id)
                            }
                            
                            if activeRing.tools.count >= LauncherRing.maxTools {
                                Text(I18n.localized("launcher_ring_actions_limit", language: state.language))
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                        }
                        
                        if state.launcherRings.count > 1 {
                            Button(action: {
                                deleteRing(id: activeRing.id)
                            }) {
                                Text(I18n.localized("launcher_delete_ring", language: state.language))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.red)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.red.opacity(0.1))
                                    .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func addNewRing() {
        let newRing = LauncherRing(name: "Ring \(state.launcherRings.count + 1)")
        state.launcherRings.append(newRing)
        selectedRingId = newRing.id
    }
    
    private func deleteRing(id: UUID) {
        if let idx = state.launcherRings.firstIndex(where: { $0.id == id }) {
            state.launcherRings.remove(at: idx)
            if let first = state.launcherRings.first {
                selectedRingId = first.id
            }
        }
    }
    
    private func renameRing(id: UUID, to name: String) {
        if let idx = state.launcherRings.firstIndex(where: { $0.id == id }) {
            state.launcherRings[idx].name = name
        }
    }
    
    @ViewBuilder
    private func popoverToolList(for ringId: UUID) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text(I18n.localized("launcher_ring_add_action", language: state.language))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                    .padding(.bottom, 4)
                
                ForEach(state.quickTools) { tool in
                    Button(action: {
                        appendTool(tool, to: ringId)
                    }) {
                        HStack(spacing: 6) {
                            if case .builtIn(let type) = tool {
                                Text("\(type.icon) \(type.localizedName(language: state.language))")
                            } else if case .appShortcut(_, let name, let path, _) = tool {
                                AppIconView(path: path)
                                    .frame(width: 16, height: 16)
                                Text(name)
                            }
                            Spacer()
                        }
                        .font(.system(size: 11))
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }

                Divider()

                Button(action: {
                    addExternalApp(to: ringId)
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.app")
                        Text(I18n.localized("quick_actions_add_app", language: state.language))
                        Spacer()
                    }
                    .font(.system(size: 11))
                    .foregroundColor(.accentColor)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .frame(width: 180)
        }
        .frame(maxHeight: 240)
    }
    
    private func appendTool(_ tool: QuickTool, to ringId: UUID) {
        guard let idx = state.launcherRings.firstIndex(where: { $0.id == ringId }) else { return }
        guard state.launcherRings[idx].tools.count < LauncherRing.maxTools else { return }
        state.launcherRings[idx].tools.append(tool)
        showingAddActionPopover = false
    }
    
    private func removeTool(from ringId: UUID, at index: Int) {
        guard let idx = state.launcherRings.firstIndex(where: { $0.id == ringId }) else { return }
        guard state.launcherRings[idx].tools.indices.contains(index) else { return }
        state.launcherRings[idx].tools.remove(at: index)
    }
    
    private func moveTool(in ringId: UUID, from source: IndexSet, to destination: Int) {
        guard let idx = state.launcherRings.firstIndex(where: { $0.id == ringId }) else { return }
        state.launcherRings[idx].tools.move(fromOffsets: source, toOffset: destination)
    }
    
    private func addExternalApp(to ringId: UUID) {
        showingAddActionPopover = false
        
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                let name = url.deletingPathExtension().lastPathComponent
                let path = url.path
                let bookmarkData = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                
                let newTool = QuickTool.appShortcut(id: UUID(), name: name, path: path, bookmarkData: bookmarkData)
                
                Task { @MainActor in
                    appendTool(newTool, to: ringId)
                }
            }
        }
    }
}
