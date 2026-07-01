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
    @State private var selectedTab: String = "rest"
    
    @ObservedObject private var clamshell = ClamshellManager.shared
    @AppStorage("batteryProtectionThreshold") private var batteryProtectionThreshold = 0

    // Sub-tab selection identifiers
    @State private var selectedRestSubTab: String = "goal"
    @State private var selectedWaterSubTab: String = "general"
    @State private var selectedBehaviorSubTab: String = "pet"
    @State private var selectedSystemSubTab: String = "general"
    @State private var selectedClipboardSubTab: String = "general"

    private var restSubTabs: [(id: String, key: String)] {
        [
            ("goal", "settings_subtab_goal"),
            ("durations", "settings_subtab_durations"),
            ("alerts", "settings_subtab_alerts")
        ]
    }

    private var waterSubTabs: [(id: String, key: String)] {
        [
            ("general", "settings_subtab_general"),
            ("schedule", "settings_subtab_schedule"),
            ("goal", "settings_subtab_goal")
        ]
    }

    private var behaviorSubTabs: [(id: String, key: String)] {
        [
            ("pet", "settings_subtab_pet"),
            ("personality", "settings_subtab_personality"),
            ("interactions", "settings_subtab_interactions")
        ]
    }

    private var systemSubTabs: [(id: String, key: String)] {
        [
            ("general", "settings_subtab_general"),
            ("power", "settings_subtab_power"),
            ("about", "settings_subtab_about")
        ]
    }

    private var clipboardSubTabs: [(id: String, key: String)] {
        [
            ("general", "clipboard_tab_general"),
            ("storage", "clipboard_tab_storage"),
            ("pinned", "clipboard_tab_pinned"),
            ("ignored", "clipboard_tab_ignored")
        ]
    }

    private var sidebarItems: [SidebarItem] {
        let hasPendingUpdate = UpdateChecker.shared.hasPendingUpdate
        return [
            SidebarItem(id: "rest", title: I18n.localized("settings_tab_rest", language: state.language), icon: "timer"),
            SidebarItem(id: "water", title: I18n.localized("settings_tab_water", language: state.language), icon: "drop.fill"),
            SidebarItem(id: "behavior", title: I18n.localized("settings_section_behavior", language: state.language), icon: "cat.circle"),
            SidebarItem(id: "keydrop", title: I18n.localized("settings_tab_keydrop", language: state.language), icon: "keyboard"),
            SidebarItem(id: "clipboard", title: I18n.localized("settings_tab_clipboard", language: state.language), icon: "clipboard"),
            SidebarItem(id: "shelf", title: I18n.localized("settings_tab_shelf", language: state.language), icon: "tray.and.arrow.down"),
            SidebarItem(id: "quick_actions", title: I18n.localized("menu_quick_actions", language: state.language), icon: "bolt.fill"),
            SidebarItem(id: "memos", title: "Memos", icon: "note.text"),
            SidebarItem(id: "permissions", title: I18n.localized("settings_tab_permissions", language: state.language), icon: "lock.shield"),
            SidebarItem(id: "system", title: I18n.localized("settings_section_system", language: state.language), icon: "gearshape", hasBadge: hasPendingUpdate),
        ]
    }

    var body: some View {
        HStack(spacing: 0) {
            SidebarTabBar(items: sidebarItems, selection: $selectedTab)
            Divider()
            
            VStack(alignment: .leading, spacing: 0) {
                // Second level: Pill Tabs
                HStack {
                    subTabBar
                    Spacer()
                    if selectedTab == "rest" {
                        Button(action: {
                            state.resetIntervalsToDefaults()
                        }) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(I18n.localized("settings_restore_defaults", language: state.language))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 16)
                
                // Third level: Card List
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        Group {
                            switch selectedTab {
                            case "water": waterCards
                            case "behavior": behaviorCards
                            case "keydrop": keyDropCards
                            case "clipboard": ClipboardSettingsView(selectedTab: selectedClipboardSubTab)
                            case "shelf": ShelfSettingsView()
                            case "quick_actions": QuickActionsSettingsView(state: state)
                            case "memos": MemosSettingsView(state: state)
                            case "permissions": permissionsCards
                            case "system": systemCards
                            default: restCards
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 580, height: 550)
        .background(VisualEffectView().ignoresSafeArea())
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
            selectedTab = "permissions"
        }
        .onAppear {
            clamshell.syncWithSystem()
            applyPendingNavigationTarget()
        }
        .onChange(of: state.settingsNavigationTarget) { _, _ in
            applyPendingNavigationTarget()
        }
    }

    private func applyPendingNavigationTarget() {
        switch state.settingsNavigationTarget {
        case .update:
            selectedTab = "system"
            selectedSystemSubTab = "about"
            state.settingsNavigationTarget = nil
        case .permissions:
            selectedTab = "permissions"
            state.settingsNavigationTarget = nil
        case .memos:
            selectedTab = "memos"
            state.settingsNavigationTarget = nil
        case nil:
            break
        }
    }

    private func subTabBinding(for selection: Binding<String>, tabs: [(id: String, key: String)]) -> Binding<String> {
        Binding(
            get: {
                let currentId = selection.wrappedValue
                let key = tabs.first { $0.id == currentId }?.key ?? tabs[0].key
                return I18n.localized(key, language: state.language)
            },
            set: { newValue in
                if let id = tabs.first(where: { I18n.localized($0.key, language: state.language) == newValue })?.id {
                    selection.wrappedValue = id
                }
            }
        )
    }

    @ViewBuilder
    private var subTabBar: some View {
        switch selectedTab {
        case "water":
            PillTabBar(items: waterSubTabs.map { I18n.localized($0.key, language: state.language) },
                       selection: subTabBinding(for: $selectedWaterSubTab, tabs: waterSubTabs))
        case "behavior":
            PillTabBar(items: behaviorSubTabs.map { I18n.localized($0.key, language: state.language) },
                       selection: subTabBinding(for: $selectedBehaviorSubTab, tabs: behaviorSubTabs))
        case "system":
            let aboutTitle = I18n.localized("settings_subtab_about", language: state.language)
            PillTabBar(items: systemSubTabs.map { I18n.localized($0.key, language: state.language) },
                       badgeItems: UpdateChecker.shared.hasPendingUpdate ? [aboutTitle] : [],
                       selection: subTabBinding(for: $selectedSystemSubTab, tabs: systemSubTabs))
        case "keydrop":
            EmptyView()
        case "clipboard":
            PillTabBar(items: clipboardSubTabs.map { I18n.localized($0.key, language: state.language) },
                       selection: subTabBinding(for: $selectedClipboardSubTab, tabs: clipboardSubTabs))
        case "shelf":
            EmptyView()
        case "quick_actions":
            EmptyView()
        case "memos":
            EmptyView()
        case "permissions":
            EmptyView()
        default:
            PillTabBar(items: restSubTabs.map { I18n.localized($0.key, language: state.language) },
                       selection: subTabBinding(for: $selectedRestSubTab, tabs: restSubTabs))
        }
    }

    @ViewBuilder
    private var restCards: some View {
        if selectedRestSubTab == "goal" {
            SettingsCard(
                icon: "target",
                iconColor: .orange,
                title: I18n.localized("stats_todays_goal", language: state.language),
                description: I18n.localizedFormat("stats_setting_goal", language: state.language, Int64(state.dailyWorkGoal))
            ) {
                settingSlider(value: Binding(get: { Double(state.dailyWorkGoal) }, set: { state.dailyWorkGoal = Int($0) }), in: 4...12, step: 1, unit: "unit_hours")
            }
        } else if selectedRestSubTab == "durations" {
            VStack(spacing: 16) {
                SettingsCard(
                    icon: "timer",
                    iconColor: .blue,
                    title: I18n.localized("settings_work_duration", language: state.language),
                    description: I18n.localized("settings_work_duration_desc", language: state.language)
                ) {
                    settingSlider(value: Binding(get: { Double(state.workDurationMinutes) }, set: { state.workDurationMinutes = Int($0) }), in: 15...120, step: 5, unit: "unit_minutes_short")
                }

                SettingsCard(
                    icon: "clock.fill",
                    iconColor: .green,
                    title: I18n.localized("settings_rest_duration", language: state.language),
                    description: I18n.localized("settings_rest_duration_desc", language: state.language)
                ) {
                    settingSlider(value: Binding(get: { Double(state.restDurationMinutes) }, set: { state.restDurationMinutes = Int($0) }), in: 1...30, step: 1, unit: "unit_minutes_short")
                }

                SettingsCard(
                    icon: "arrow.clockwise",
                    iconColor: .purple,
                    title: I18n.localized("settings_rest_to_reset", language: state.language),
                    description: I18n.localized("settings_rest_to_reset_desc", language: state.language)
                ) {
                    settingSlider(value: Binding(get: { Double(state.restToResetMinutes) }, set: { state.restToResetMinutes = Int($0) }), in: 2...30, step: 1, unit: "unit_minutes_short")
                }
            }
        } else if selectedRestSubTab == "alerts" {
            SettingsCard(
                icon: "bell.badge.fill",
                iconColor: .red,
                title: I18n.localized("settings_alert_notice", language: state.language),
                description: I18n.localized("settings_alert_notice_desc", language: state.language)
            ) {
                settingSlider(value: Binding(get: { Double(state.alertBeforeRestMinutes) }, set: { state.alertBeforeRestMinutes = Int($0) }), in: 1...15, step: 1, unit: "unit_minutes_short")
            }
        }
    }

    @ViewBuilder
    private var waterCards: some View {
        switch selectedWaterSubTab {
        case "general":
            SettingsCard(icon: "drop.fill", iconColor: .blue, title: I18n.localized("water_settings_enabled", language: state.language), description: nil) {
                Toggle(isOn: $state.waterReminderEnabled) {
                    Text(I18n.localized("water_settings_enabled", language: state.language))
                }
                .toggleStyle(.switch)
            }
        case "schedule":
            VStack(spacing: 16) {
                SettingsCard(icon: "clock.fill", iconColor: .cyan, title: I18n.localized("water_settings_mode", language: state.language), description: nil) {
                    Picker("", selection: $state.waterReminderMode) {
                        Text(I18n.localized("water_settings_mode_rhythm", language: state.language)).tag(AppState.WaterReminderMode.followRhythm)
                        Text(I18n.localized("water_settings_mode_custom", language: state.language)).tag(AppState.WaterReminderMode.custom)
                    }
                    .pickerStyle(.segmented)
                }

                if state.waterReminderMode == .custom {
                    SettingsCard(icon: "timer", iconColor: .blue, title: I18n.localized("water_settings_interval", language: state.language), description: nil) {
                        settingSlider(value: Binding(get: { Double(state.waterCustomInterval) }, set: { state.waterCustomInterval = Int($0) }), in: 15...120, step: 5, unit: "unit_minutes_short")
                    }
                }
            }
        case "goal":
            SettingsCard(icon: "target", iconColor: .orange, title: I18n.localized("water_settings_goal", language: state.language), description: nil) {
                settingSlider(value: Binding(get: { Double(state.dailyWaterGoal) }, set: { state.dailyWaterGoal = Int($0) }), in: 4...20, step: 1, unit: "unit_cups")
            }
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var behaviorCards: some View {
        switch selectedBehaviorSubTab {
        case "pet":
            SettingsCard(icon: "pawprint.fill", iconColor: .orange, title: I18n.localized("settings_pet_selection", language: state.language), description: nil) {
                petSelectionGrid
            }
        case "personality":
            SettingsCard(icon: "person.text.rectangle", iconColor: .purple, title: I18n.localized("settings_personality", language: state.language), description: I18n.localized("settings_personality_desc", language: state.language)) {
                Picker("", selection: $state.selectedPersonality) {
                    Text(I18n.localized("settings_personality_gentle", language: state.language)).tag(PetPersonality.gentle)
                    Text(I18n.localized("settings_personality_strict", language: state.language)).tag(PetPersonality.strict)
                    Text(I18n.localized("settings_personality_tsundere", language: state.language)).tag(PetPersonality.tsundere)
                }
                .pickerStyle(.segmented)
            }
        case "interactions":
            VStack(spacing: 16) {
                SettingsCard(icon: "hand.tap", iconColor: .blue, title: I18n.localized("settings_cursor_chasing", language: state.language), description: I18n.localized("settings_cursor_chasing_desc", language: state.language)) {
                    Toggle(isOn: $state.enableCursorChasing) {
                        Text(I18n.localized("settings_cursor_chasing", language: state.language))
                    }
                    .toggleStyle(.switch)
                }

                SettingsCard(icon: "keyboard", iconColor: .red, title: I18n.localized("settings_global_scold", language: state.language), description: I18n.localized("settings_global_scold_desc", language: state.language)) {
                    globalScoldToggle
                }

                SettingsCard(icon: "eye", iconColor: .green, title: I18n.localized("settings_preview_title", language: state.language), description: I18n.localized("settings_preview_desc", language: state.language)) {
                    previewButtons
                }
            }
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var systemCards: some View {
        switch selectedSystemSubTab {
        case "general":
            VStack(spacing: 16) {
                SettingsCard(icon: "character.bubble", iconColor: .blue, title: I18n.localized("settings_language", language: state.language), description: nil) {
                    Picker("", selection: $state.language) {
                        ForEach(AppState.AppLanguage.allCases) { lang in
                            Text(lang.displayName(currentLanguage: state.language)).tag(lang)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                SettingsCard(icon: "arrow.right.circle", iconColor: .green, title: I18n.localized("settings_launch_at_login", language: state.language), description: I18n.localized("settings_launch_at_login_desc", language: state.language)) {
                    Toggle(isOn: Binding(
                        get: { launchManager.isLaunchAtLoginEnabled },
                        set: { launchManager.toggleLaunchAtLogin(enabled: $0) }
                    )) {
                        Text(I18n.localized("settings_launch_at_login", language: state.language))
                    }
                    .toggleStyle(.switch)
                }

                SettingsCard(
                    icon: "cat",
                    iconColor: .gray,
                    title: I18n.localized("settings_classic_tray_icon", language: state.language),
                    description: I18n.localized("settings_classic_tray_icon_desc", language: state.language)
                ) {
                    Toggle(isOn: $state.useClassicTrayIcon) {
                        Text(I18n.localized("settings_classic_tray_icon", language: state.language))
                    }
                    .toggleStyle(.switch)
                }
            }
        case "power":
            powerCards
        case "about":
            VStack(spacing: 24) {
                let version = Bundle.main.appVersion
                
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
                    
                    Text("\(I18n.localizedFormat("settings_version", language: state.language, version)) (\(currentGitCommit))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Text(I18n.localized("settings_about_description", language: state.language))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
                .padding(.top, 16)
                
                updateCard
            }
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var powerCards: some View {
        VStack(spacing: 16) {
            SettingsCard(
                icon: "display",
                iconColor: .blue,
                title: I18n.localized("power_clamshell_title", language: state.language),
                description: nil,
                tip: I18n.localized("power_clamshell_desc", language: state.language)
            ) {
                HStack {
                    Toggle(isOn: Binding(
                        get: { clamshell.isEnabledGlobally },
                        set: { newValue in
                            if !SudoersManager.isConfigured() {
                                showSudoersNSAlert(pendingValue: newValue)
                            } else {
                                clamshell.setClamshellMode(enabled: newValue)
                            }
                        }
                    )) {
                        Text(I18n.localized("power_clamshell_toggle", language: state.language))
                    }
                    .toggleStyle(.switch)
                    
                    if clamshell.isExternallyEnabled {
                        InlineTipButton(
                            tip: I18n.localized("power_clamshell_external_tip", language: state.language),
                            iconColor: .orange
                        )
                    }
                }
            }
            
            SettingsCard(
                icon: "battery.100.bolt",
                iconColor: .green,
                title: I18n.localized("power_battery_title", language: state.language),
                description: I18n.localized("power_battery_desc", language: state.language)
            ) {
                settingSlider(
                    value: Binding(get: { Double(batteryProtectionThreshold) }, set: { batteryProtectionThreshold = Int($0) }),
                    in: 0...50,
                    step: 5,
                    unit: "power_battery_unit"
                )
            }
        }
    }

    @ViewBuilder
    private var updateCard: some View {
        let checker = UpdateChecker.shared
        SettingsCard(
            icon: "arrow.clockwise.circle",
            iconColor: .blue,
            title: I18n.localized("settings_check_updates", language: state.language),
            description: checker.lastCheckedAt.map { date in
                let formatter = DateFormatter()
                formatter.dateStyle = .short
                formatter.timeStyle = .short
                return I18n.localizedFormat("settings_update_last_checked", language: state.language, formatter.string(from: date))
            }
        ) {
            VStack(alignment: .leading, spacing: 12) {
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
    private func settingSlider(value: Binding<Double>, in range: ClosedRange<Double>, step: Double, unit: String) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(I18n.localizedFormat(unit, language: state.language, Int64(value.wrappedValue)))
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.orange)
            Slider(value: value, in: range, step: step)
        }
    }

    @ViewBuilder
    private var petSelectionGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 70, maximum: 70), spacing: 16)],
            alignment: .leading,
            spacing: 16
        ) {
            ForEach(AppState.PetType.allCases) { pet in
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
                .onTapGesture {
                    withAnimation(.spring(response: 0.3)) {
                        state.selectedPet = pet
                    }
                }
            }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var globalScoldToggle: some View {
        Toggle(isOn: Binding(
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
                        selectedTab = "permissions"
                    }
                } else {
                    state.enableGlobalKeyboardScold = false
                    isAwaitingAccessibility = false
                }
            }
        )) {
            Text(I18n.localized("settings_global_scold", language: state.language))
        }
        .toggleStyle(.switch)
    }

    @ViewBuilder
    private var keyDropToggle: some View {
        Toggle(isOn: Binding(
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
                        selectedTab = "permissions"
                    }
                } else {
                    state.keyDropEnabled = false
                    isAwaitingAccessibilityForKeyDrop = false
                }
            }
        )) {
            Text(I18n.localized("keydrop_enabled", language: state.language))
        }
        .toggleStyle(.switch)
    }

    @ViewBuilder
    private var keyDropCards: some View {
        VStack(spacing: 16) {
            SettingsCard(
                icon: "keyboard",
                iconColor: .purple,
                title: I18n.localized("keydrop_enabled", language: state.language),
                description: I18n.localized("keydrop_enabled_desc", language: state.language)
            ) {
                keyDropToggle
            }

            SettingsCard(
                icon: "command",
                iconColor: .blue,
                title: I18n.localized("keydrop_shortcut", language: state.language),
                description: I18n.localized("keydrop_shortcut_desc", language: state.language)
            ) {
                HStack {
                    Spacer()
                    KeyboardShortcuts.Recorder(for: .togglePanel)
                }
            }

            SettingsCard(
                icon: "square.and.pencil",
                iconColor: .orange,
                title: I18n.localized("keydrop_manage_title", language: state.language),
                description: I18n.localized("keydrop_manage_desc", language: state.language)
            ) {
                HStack {
                    Spacer()
                    Button(action: {
                        NotificationCenter.default.post(name: NSNotification.Name("OpenSnippetManagerWindow"), object: nil)
                    }) {
                        Text(I18n.localized("keydrop_open_manager_btn", language: state.language))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var permissionsCards: some View {
        SettingsCard(
            icon: "lock.shield",
            iconColor: accessibilityStatus ? .green : .red,
            title: I18n.localized("accessibility_card_title", language: state.language),
            description: I18n.localized("accessibility_card_desc", language: state.language)
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(accessibilityStatus ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(accessibilityStatus ? I18n.localized("accessibility_status_granted", language: state.language) : I18n.localized("accessibility_status_denied", language: state.language))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(accessibilityStatus ? .green : .red)
                }
                
                if !accessibilityStatus {
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
                }
            }
        }
    }

    @ViewBuilder
    private var previewButtons: some View {
        HStack(spacing: 12) {
            if state.isPreviewing {
                Button(action: {
                    CatOverlayController.shared.stopPreview()
                }) {
                    Text(I18n.localized("settings_preview_stop", language: state.language))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
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
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.1))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)

                Button(action: {
                    CatOverlayController.shared.previewResting()
                }) {
                    Text(I18n.localized("settings_preview_resting", language: state.language))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.1))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct VisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = .sidebar
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
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
        VStack(spacing: 16) {
            // Card 1: Original Quick Actions Menu Settings
            SettingsCard(
                icon: "bolt.fill",
                iconColor: .orange,
                title: I18n.localized("menu_quick_actions", language: state.language),
                description: I18n.localized("quick_actions_settings_desc", language: state.language)
            ) {
                QuickActionsListEditor(state: state)
            }
            
            // Card 2: Launcher Trigger Settings
            SettingsCard(
                icon: "keyboard",
                iconColor: .blue,
                title: I18n.localized("launcher_settings_title", language: state.language),
                description: nil
            ) {
                LauncherTriggerSettingsView(state: state)
            }
            
            // Card 3: Launcher Rings Layout Config
            if state.launcherEnabled {
                SettingsCard(
                    icon: "circle.circle",
                    iconColor: .purple,
                    title: I18n.localized("launcher_ring_editor_title", language: state.language),
                    description: nil
                ) {
                    LauncherRingsEditorView(state: state)
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
                        } else if case .appShortcut(_, let name, _, _) = tool {
                            Text("📱 \(name)")
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
                        HStack {
                            if case .builtIn(let type) = tool {
                                Text("\(type.icon) \(type.localizedName(language: state.language))")
                            } else if case .appShortcut(_, let name, _, _) = tool {
                                Text("🚀 \(name)")
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
                    HStack {
                        Text("➕ \(I18n.localized("quick_actions_add_app", language: state.language))")
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

struct InlineTipButton: View {
    let tip: String
    var iconColor: Color = .secondary
    @State private var showTipPopover = false

    var body: some View {
        Button(action: { showTipPopover.toggle() }) {
            Image(systemName: "info.circle")
                .foregroundColor(iconColor)
                .font(.system(size: 12))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showTipPopover, arrowEdge: .bottom) {
            Text(tip)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .frame(maxWidth: 220)
        }
    }
}
