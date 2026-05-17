import SwiftUI
import Charts

struct DailyWork: Identifiable {
    let id = UUID()
    let date: Date
    let hours: Double
}

struct SettingsView: View {
    @Bindable var state: AppState
    @Bindable var launchManager = LaunchManager.shared
    @State private var selectedTab: Int = 0

    // Snapshot of chart data to prevent jitter from real-time updates
    @State private var chartDataSnapshot: [DailyWork] = []

    // Track expanded states for the "Drawers"
    @State private var intervalsExpanded = true
    @State private var behaviorExpanded = true
    @State private var systemExpanded = true

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 8)

            // Tab Picker
            Picker("", selection: $selectedTab) {
                Text(I18n.localized("settings_tab_settings", language: state.language)).tag(0)
                Text(I18n.localized("settings_tab_statistics", language: state.language)).tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)
            .padding(.bottom, 16)

            Divider()

            // Content
            ZStack {
                if selectedTab == 0 {
                    settingsContent
                } else {
                    statsContent
                        .onAppear {
                            refreshChartSnapshot()
                        }
                }
            }
            .onChange(of: selectedTab) { _, newValue in
                if newValue == 1 {
                    refreshChartSnapshot()
                }
            }

            // Footer: Reset to Defaults (Only show on Settings tab)
            if selectedTab == 0 {
                Divider()
                HStack {
                    Button(action: {
                        state.resetToDefaults()
                    }) {
                        Label {
                            Text(I18n.localized("settings_restore_defaults", language: state.language))
                        } icon: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Spacer()

                    Text(I18n.localized("settings_version", language: state.language))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(Color.primary.opacity(0.02))
            }
        }
        .frame(width: 450, height: 600)
        .background(VisualEffectView().ignoresSafeArea())
    }

    private var settingsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Section: Time Intervals
                DisclosureGroup(isExpanded: $intervalsExpanded) {
                    VStack(spacing: 16) {
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
                    .padding(.top, 12)
                } label: {
                    Label {
                        Text(I18n.localized("settings_section_intervals", language: state.language))
                    } icon: {
                        Image(systemName: "timer")
                    }
                    .font(.headline)
                    .foregroundStyle(.primary)
                }
                .padding()
                .background(Color.primary.opacity(0.03))
                .cornerRadius(12)

                // Section: Behavior
                DisclosureGroup(isExpanded: $behaviorExpanded) {
                    VStack(alignment: .leading, spacing: 16) {
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
                    .padding(.top, 12)
                } label: {
                    Label {
                        Text(I18n.localized("settings_section_behavior", language: state.language))
                    } icon: {
                        Image(systemName: "cat.circle")
                    }
                    .font(.headline)
                    .foregroundStyle(.primary)
                }
                .padding()
                .background(Color.primary.opacity(0.03))
                .cornerRadius(12)

                // Section: System
                 DisclosureGroup(isExpanded: $systemExpanded) {
                    VStack(alignment: .leading, spacing: 16) {
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
                    .padding(.top, 12)
                } label: {
                    Label {
                        Text(I18n.localized("settings_section_system", language: state.language))
                    } icon: {
                        Image(systemName: "gearshape")
                    }
                    .font(.headline)
                    .foregroundStyle(.primary)
                }
                .padding()
                .background(Color.primary.opacity(0.03))
                .cornerRadius(12)
            }
            .padding(24)
        }
    }

    private var statsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // 1. Daily Goal Progress
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label {
                            Text(I18n.localized("stats_todays_goal", language: state.language))
                        } icon: {
                            Image(systemName: "target")
                        }
                        .font(.headline)
                        Spacer()
                        Text(I18n.localizedFormat("unit_hours_short", language: state.language, String(format: "%.1f", state.totalWorkToday / 3600), Int64(state.dailyWorkGoal)))
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(.orange)
                    }

                    ProgressView(value: min(state.totalWorkToday / (Double(state.dailyWorkGoal) * 3600), 1.0))
                        .tint(.orange)
                        .scaleEffect(x: 1, y: 2, anchor: .center)
                        .padding(.vertical, 8)

                    Text(I18n.localizedFormat("stats_setting_goal", language: state.language, Int64(state.dailyWorkGoal)))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Slider(value: Binding(get: { Double(state.dailyWorkGoal) },
                                         set: { state.dailyWorkGoal = Int($0) }),
                           in: 4...12, step: 1)
                }
                .padding()
                .background(Color.primary.opacity(0.03))
                .cornerRadius(12)

                // 2. 7-Day Trend Chart
                VStack(alignment: .leading, spacing: 16) {
                    Label {
                        Text(I18n.localized("stats_last_7_days", language: state.language))
                    } icon: {
                        Image(systemName: "chart.bar.xaxis")
                    }
                    .font(.headline)

                    Chart {
                        ForEach(chartDataSnapshot) { day in
                            BarMark(
                                x: .value(I18n.localized("stats_chart_date", language: state.language), day.date, unit: .day),
                                y: .value(I18n.localized("stats_chart_hours", language: state.language), day.hours)
                            )
                            .foregroundStyle(.orange.gradient)
                            .cornerRadius(4)
                            .annotation(position: .top) {
                                if day.hours > 0 {
                                    Text(String(format: "%.1f", day.hours))
                                        .font(.system(size: 8))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        RuleMark(y: .value("Goal", Double(state.dailyWorkGoal)))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                            .foregroundStyle(.orange.opacity(0.5))
                            .annotation(position: .top, alignment: .trailing) {
                                Text(I18n.localized("stats_chart_goal", language: state.language))
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                    }
                    .frame(height: 200)
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day)) { value in
                            AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading)
                    }
                    .chartYScale(domain: 0...max(Double(state.dailyWorkGoal) + 1, (chartDataSnapshot.map { $0.hours }.max() ?? 0) + 1))
                }
                .padding()
                .background(Color.primary.opacity(0.03))
                .cornerRadius(12)

                // Tip
                HStack {
                    Image(systemName: "info.circle")
                    Text(I18n.localized("stats_midnight_reset_tip", language: state.language))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            }
            .padding(24)
        }
    }

    private var headerView: some View {
        HStack(spacing: 12) {
            Image(systemName: "cat.fill")
                .font(.system(size: 32))
                .foregroundStyle(.orange)

            VStack(alignment: .leading) {
                Text(I18n.localized("settings_window_title", language: state.language))
                    .font(.headline)
                Text(I18n.localized("settings_header_subtitle", language: state.language))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
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

    private func refreshChartSnapshot() {
        let calendar = Calendar.current
        let now = Date()
        var days: [DailyWork] = []

        for i in (0..<7).reversed() {
            if let date = calendar.date(byAdding: .day, value: -i, to: now) {
                let key = dateKey(for: date)
                let seconds = state.workHistory[key] ?? 0
                let totalSeconds = (i == 0) ? max(seconds, state.totalWorkToday) : seconds
                days.append(DailyWork(date: date, hours: totalSeconds / 3600))
            }
        }
        chartDataSnapshot = days
    }

    private func dateKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
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
