import SwiftUI
import Charts

struct DailyWork: Identifiable {
    let id = UUID()
    let date: Date
    let hours: Double
}

/// 统计页。从「健康作息」推进进入，占满设置详情面板宽度。
///
/// 自身**不包 ScrollView** —— 外层 detail: 闭包已经提供了滚动。再套一层纵向 ScrollView
/// 会给内容传无界高度建议，与外层滚动互相打架（同一个坑在常用语管理器上已经踩过一次）。
struct StatsView: View {
    @Bindable var state: AppState

    @State private var chartDataSnapshot: [DailyWork] = []
    @State private var isLogExpanded = false
    @State private var isChartExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            todayOverviewCard

            collapsibleSection(
                title: I18n.localized("stats_today_log_section", language: state.language),
                isExpanded: $isLogExpanded
            ) {
                TodayReviewView(logs: state.dailyLogs)
            }

            collapsibleSection(
                title: I18n.localized("stats_last_7_days", language: state.language),
                isExpanded: $isChartExpanded
            ) {
                chartContent
            }
        }
        .onAppear { refreshChartSnapshot() }
    }

    // MARK: - 今日概览

    private var todayOverviewCard: some View {
        SettingsGroup(I18n.localized("stats_today_overview", language: state.language)) {
            VStack(spacing: 0) {
                metricRow(
                    icon: "target",
                    color: .teal,
                    label: I18n.localized("stats_metric_work", language: state.language),
                    value: I18n.localizedFormat("unit_hours_short", language: state.language, String(format: "%.1f", state.totalWorkToday / 3600), Int64(state.dailyWorkGoal)),
                    progress: min(state.totalWorkToday / (Double(state.dailyWorkGoal) * 3600), 1.0)
                ) {
                    EmptyView()
                }

                SettingsRowDivider()

                metricRow(
                    icon: "drop.fill",
                    color: .blue,
                    label: I18n.localized("stats_metric_water", language: state.language),
                    value: "\(state.todayWaterCups) / \(I18n.localizedFormat("unit_cups", language: state.language, Int64(state.dailyWaterGoal)))",
                    progress: min(Double(state.todayWaterCups) / Double(state.dailyWaterGoal), 1.0)
                ) {
                    Button(action: {
                        state.todayWaterCups += 1
                        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(I18n.localized("water_add_cup", language: state.language))
                }
            }
        }
    }

    /// 一个指标行：图标 + 名称 + 数值 + 进度条，右侧可选一个操作。
    /// 抽出来是为了让两行的排版由构造保证一致，而不是靠两处各写一遍。
    private func metricRow<Trailing: View>(
        icon: String,
        color: Color,
        label: String,
        value: String,
        progress: Double,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 16)
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 8)
                Text(value)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
                trailing()
            }
            ProgressView(value: progress)
                .tint(color)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var chartContent: some View {
        Chart {
            ForEach(chartDataSnapshot) { day in
                BarMark(
                    x: .value(I18n.localized("stats_chart_date", language: state.language), day.date, unit: .day),
                    y: .value(I18n.localized("stats_chart_hours", language: state.language), day.hours)
                )
                .foregroundStyle(.teal.gradient)
                .cornerRadius(4)
            }
            RuleMark(y: .value("Goal", Double(state.dailyWorkGoal)))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                .foregroundStyle(.teal.opacity(0.5))
        }
        .frame(height: 180)
    }

    /// 设置风格的可展开卡片：整行可点，右侧 chevron 指示展开态。
    /// 容器与 SettingsGroup 同族（controlBackgroundColor + 圆角 10 + 细描边），
    /// 这样它和设置页其它卡片看起来是一家的。
    private func collapsibleSection<Content: View>(
        title: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                    Spacer(minLength: 8)
                    Image(systemName: isExpanded.wrappedValue ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary.opacity(0.6))
                        .frame(width: 16, height: 16)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded.wrappedValue {
                Divider()
                    .padding(.horizontal, 12)

                content()
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    // MARK: - 数据

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
