import SwiftUI
import Charts

struct DailyWork: Identifiable {
    let id = UUID()
    let date: Date
    let hours: Double
}

struct StatsView: View {
    @Bindable var state: AppState
    @State private var selectedTab: Int = 0
    @State private var chartDataSnapshot: [DailyWork] = []

    var body: some View {
        VStack(spacing: 0) {
            // Tab Picker
            Picker("", selection: $selectedTab) {
                Text(I18n.localized("settings_tab_statistics", language: state.language)).tag(0)
                Text(I18n.localized("settings_tab_today_review", language: state.language)).tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 16)

            Divider()

            Group {
                if selectedTab == 0 {
                    statsContent
                } else {
                    TodayReviewView(logs: state.dailyLogs)
                }
            }
        }
        .frame(width: 420, height: 480)
        .background(VisualEffectView().ignoresSafeArea())
        .onAppear { refreshChartSnapshot() }
    }

    private var statsContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                // Goal Progress
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label {
                            Text(I18n.localized("stats_todays_goal", language: state.language))
                        } icon: { Image(systemName: "target") }
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
                }
                .padding()
                .background(Color.primary.opacity(0.03))
                .cornerRadius(12)

                // 7-Day Chart
                VStack(alignment: .leading, spacing: 16) {
                    Label {
                        Text(I18n.localized("stats_last_7_days", language: state.language))
                    } icon: { Image(systemName: "chart.bar.xaxis") }
                    .font(.headline)

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
                    .frame(height: 200)
                }
                .padding()
                .background(Color.primary.opacity(0.03))
                .cornerRadius(12)
            }
            .padding(24)
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
