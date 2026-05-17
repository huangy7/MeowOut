import SwiftUI

struct SettingsView: View {
    @Bindable var state: AppState
    @Bindable var launchManager = LaunchManager.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        TabView {
            intervalsTab
                .tabItem { Label(I18n.localized("settings_section_intervals", language: state.language), systemImage: "timer") }
            
            behaviorTab
                .tabItem { Label(I18n.localized("settings_section_behavior", language: state.language), systemImage: "cat.circle") }
            
            systemTab
                .tabItem { Label(I18n.localized("settings_section_system", language: state.language), systemImage: "gearshape") }
        }
        .padding(20)
        .frame(width: 450, height: 400)
        .background(VisualEffectView().ignoresSafeArea())
    }

    private var intervalsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text(I18n.localized("settings_section_intervals", language: state.language))
                        .font(.headline)
                    Spacer()
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
                .padding(.bottom, 4)

                // New Location for Daily Goal Slider
                settingRow(
                    title: I18n.localized("stats_todays_goal", language: state.language),
                    description: I18n.localizedFormat("stats_setting_goal", language: state.language, Int64(state.dailyWorkGoal)),
                    value: "\(state.dailyWorkGoal)h"
                ) {
                    Slider(value: Binding(get: { Double(state.dailyWorkGoal) }, set: { state.dailyWorkGoal = Int($0) }), in: 4...12, step: 1)
                }
                
                Divider()
                
                settingRow(
                    title: I18n.localized("settings_work_duration", language: state.language),
                    description: I18n.localized("settings_work_duration_desc", language: state.language),
                    value: I18n.localizedFormat("unit_minutes_short", language: state.language, Int64(state.workDurationMinutes))
                ) {
                    Slider(value: Binding(get: { Double(state.workDurationMinutes) },
                                         set: { state.workDurationMinutes = Int($0) }),
                           in: 15...120, step: 5)
                }

                settingRow(
                    title: I18n.localized("settings_alert_notice", language: state.language),
                    description: I18n.localized("settings_alert_notice_desc", language: state.language),
                    value: I18n.localizedFormat("unit_minutes_short", language: state.language, Int64(state.alertBeforeRestMinutes))
                ) {
                    Slider(value: Binding(get: { Double(state.alertBeforeRestMinutes) },
                                         set: { state.alertBeforeRestMinutes = Int($0) }),
                           in: 1...15, step: 1)
                }

                settingRow(
                    title: I18n.localized("settings_rest_duration", language: state.language),
                    description: I18n.localized("settings_rest_duration_desc", language: state.language),
                    value: I18n.localizedFormat("unit_minutes_short", language: state.language, Int64(state.restDurationMinutes))
                ) {
                    Slider(value: Binding(get: { Double(state.restDurationMinutes) },
                                         set: { state.restDurationMinutes = Int($0) }),
                           in: 1...30, step: 1)
                }

                settingRow(
                    title: I18n.localized("settings_rest_to_reset", language: state.language),
                    description: I18n.localized("settings_rest_to_reset_desc", language: state.language),
                    value: I18n.localizedFormat("unit_minutes_short", language: state.language, Int64(state.restToResetMinutes))
                ) {
                    Slider(value: Binding(get: { Double(state.restToResetMinutes) },
                                         set: { state.restToResetMinutes = Int($0) }),
                           in: 2...30, step: 1)
                }
            }
        }
        .scrollIndicators(.hidden)
    }
    
    private var behaviorTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(I18n.localized("settings_personality", language: state.language))
                        .font(.subheadline)
                    Picker("", selection: $state.selectedPersonality) {
                        Text(I18n.localized("settings_personality_gentle", language: state.language)).tag(PetPersonality.gentle)
                        Text(I18n.localized("settings_personality_strict", language: state.language)).tag(PetPersonality.strict)
                        Text(I18n.localized("settings_personality_tsundere", language: state.language)).tag(PetPersonality.tsundere)
                    }
                    .pickerStyle(.segmented)
                    Text(I18n.localized("settings_personality_desc", language: state.language))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                Toggle(isOn: $state.enableCursorChasing) {
                    VStack(alignment: .leading) {
                        Text(I18n.localized("settings_cursor_chasing", language: state.language))
                        Text(I18n.localized("settings_cursor_chasing_desc", language: state.language))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
    }
    
    private var systemTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(I18n.localized("settings_language", language: state.language))
                        .font(.subheadline)
                    Picker("", selection: $state.language) {
                        ForEach(AppState.AppLanguage.allCases) { lang in
                            Text(lang.displayName(currentLanguage: state.language)).tag(lang)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Divider()

                Toggle(isOn: Binding(
                    get: { launchManager.isLaunchAtLoginEnabled },
                    set: { launchManager.toggleLaunchAtLogin(enabled: $0) }
                )) {
                    VStack(alignment: .leading) {
                        Text(I18n.localized("settings_launch_at_login", language: state.language))
                        Text(I18n.localized("settings_launch_at_login_desc", language: state.language))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private func settingRow<Content: View>(title: String, description: String, value: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.body)
                Spacer()
                Text(value)
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.orange)
                    .fontWeight(.bold)
            }

            content()

            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
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
