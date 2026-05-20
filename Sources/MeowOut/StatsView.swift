import SwiftUI
import Charts

struct DailyWork: Identifiable {
    let id = UUID()
    let date: Date
    let hours: Double
}

struct StatsView: View {
    @Bindable var state: AppState
    @State private var selectedTab: String = "statistics"
    @State private var chartDataSnapshot: [DailyWork] = []

    // Sub-tab selection identifiers
    @State private var selectedStatsSubTab: String = "work"
    @State private var selectedLogsSubTab: String = "today"

    private var statsSubTabs: [(id: String, key: String)] {
        [
            ("work", "stats_tab_work"),
            ("water", "stats_tab_water")
        ]
    }

    private var logsSubTabs: [(id: String, key: String)] {
        [
            ("today", "stats_subtab_today"),
            ("history", "stats_subtab_history")
        ]
    }

    private var sidebarItems: [SidebarItem] {
        [
            SidebarItem(id: "statistics", title: I18n.localized("settings_tab_statistics", language: state.language), icon: "chart.bar.fill"),
            SidebarItem(id: "logs", title: I18n.localized("stats_tab_logs", language: state.language), icon: "list.bullet.clipboard"),
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
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 16)
                
                // Third level: Content Area
                VStack(spacing: 0) {
                    if selectedTab == "logs" && selectedLogsSubTab == "today" {
                        TodayReviewView(logs: state.dailyLogs)
                    } else {
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 16) {
                                if selectedTab == "logs" {
                                    logsCards
                                } else {
                                    statisticsCards
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 20)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 580, height: 550)
        .background(VisualEffectView().ignoresSafeArea())
        .onAppear { refreshChartSnapshot() }
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
        case "logs":
            PillTabBar(items: logsSubTabs.map { I18n.localized($0.key, language: state.language) },
                       selection: subTabBinding(for: $selectedLogsSubTab, tabs: logsSubTabs))
        default:
            PillTabBar(items: statsSubTabs.map { I18n.localized($0.key, language: state.language) },
                       selection: subTabBinding(for: $selectedStatsSubTab, tabs: statsSubTabs))
        }
    }

    @ViewBuilder
    private var statisticsCards: some View {
        if selectedStatsSubTab == "work" {
            VStack(spacing: 16) {
                SettingsCard(
                    icon: "target",
                    iconColor: .orange,
                    title: I18n.localized("stats_todays_goal", language: state.language),
                    description: nil
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(I18n.localizedFormat("unit_hours_short", language: state.language, String(format: "%.1f", state.totalWorkToday / 3600), Int64(state.dailyWorkGoal)))
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundStyle(.orange)
                            Spacer()
                        }
                        ProgressView(value: min(state.totalWorkToday / (Double(state.dailyWorkGoal) * 3600), 1.0))
                            .tint(.orange)
                    }
                }

                SettingsCard(
                    icon: "chart.bar.xaxis",
                    iconColor: .orange,
                    title: I18n.localized("stats_last_7_days", language: state.language),
                    description: nil
                ) {
                    Chart {
                        ForEach(chartDataSnapshot) { day in
                            BarMark(
                                x: .value(I18n.localized("stats_chart_date", language: state.language), day.date, unit: .day),
                                y: .value(I18n.localized("stats_chart_hours", language: state.language), day.hours)
                            )
                            .foregroundStyle(.orange.gradient)
                            .cornerRadius(4)
                        }
                        RuleMark(y: .value("Goal", Double(state.dailyWorkGoal)))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                            .foregroundStyle(.orange.opacity(0.5))
                    }
                    .frame(height: 180)
                    .padding(.top, 8)
                }
            }
        } else {
            SettingsCard(
                icon: "drop.fill",
                iconColor: .blue,
                title: I18n.localized("water_today_label", language: state.language),
                description: nil
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("\(state.todayWaterCups)/\(state.dailyWaterGoal)")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundStyle(.blue)
                        Spacer()
                        Button(action: {
                            state.todayWaterCups += 1
                            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                        }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)
                    }

                    ProgressView(value: min(Double(state.todayWaterCups) / Double(state.dailyWaterGoal), 1.0))
                        .tint(.blue)
                }
            }
        }
    }

    @ViewBuilder
    private var logsCards: some View {
        if selectedLogsSubTab == "history" {
            VStack(spacing: 20) {
                Spacer()
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text(I18n.localized("stats_subtab_history", language: state.language))
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Coming soon")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
        }
    }

    private func refreshChartSnapshot() {
        let calendar = Calendar.current
        let now = Date()
        var days: [DailyWork] = []
        for i in (0..<7).reversed() {
            if let date = calendar.date(byAdding: .day, value: -i, to: now) {
                let key = state.dateKey(for: date)
                let seconds = state.workHistory[key] ?? 0
                let totalSeconds = (i == 0) ? max(seconds, state.totalWorkToday) : seconds
                days.append(DailyWork(date: date, hours: totalSeconds / 3600))
            }
        }
        chartDataSnapshot = days
    }
}
