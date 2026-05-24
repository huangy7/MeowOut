import SwiftUI

/// Minimum session duration to show in detailed log (seconds)
private let minSessionDuration: TimeInterval = 60

struct TodayReviewView: View {
    @Environment(AppState.self) private var state
    let logs: [SessionLog]
    @State private var isDetailExpanded = false

    /// Visible sessions: duration must be > 0 and >= minSessionDuration
    private var visibleLogs: [SessionLog] {
        logs.filter { log in
            let duration = logDuration(log)
            return duration >= minSessionDuration
        }
    }

    // MARK: - Duration helpers

    /// Clamped, non-negative duration for a log entry
    private func logDuration(_ log: SessionLog) -> TimeInterval {
        let raw = (log.endTime ?? Date()).timeIntervalSince(log.startTime)
        return max(0, raw)
    }

    // Helpers to calculate durations
    private var totalDuration: TimeInterval {
        guard let first = logs.first else { return 0 }
        return Date().timeIntervalSince(first.startTime)
    }

    private var totalWorkDuration: TimeInterval {
        visibleLogs.filter { $0.phase == .working }.reduce(0) { $0 + logDuration($1) }
    }

    private var totalRestDuration: TimeInterval {
        visibleLogs.filter { $0.phase == .resting }.reduce(0) { $0 + logDuration($1) }
    }

    private var totalOverworkingDuration: TimeInterval {
        visibleLogs.filter { $0.phase == .overworking }.reduce(0) { $0 + logDuration($1) }
    }

    private var totalBreathingDuration: TimeInterval {
        visibleLogs.filter { $0.phase == .breathing }.reduce(0) { $0 + logDuration($1) }
    }

    private var totalIdleDuration: TimeInterval {
        visibleLogs.filter { $0.phase == .idle || $0.phase == .paused || $0.phase == .alerting }
            .reduce(0) { $0 + logDuration($1) }
    }

    var body: some View {
        if logs.isEmpty {
            Text(I18n.localized("log_no_records", language: state.language)).foregroundColor(.secondary).padding()
        } else {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 30) {
                    // 1. Timeline Bar
                    VStack(alignment: .leading, spacing: 12) {
                        GeometryReader { geometry in
                            HStack(spacing: 0) {
                                ForEach(logs) { log in
                                    Rectangle()
                                        .fill(color(for: log.phase))
                                        .frame(width: max(0, width(for: log, in: geometry.size.width)))
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .frame(height: 24)

                        // Legend
                        HStack(spacing: 16) {
                            legendItem(color: .blue, text: I18n.localized("log_phase_working", language: state.language))
                            legendItem(color: .red, text: I18n.localized("log_phase_overworking", language: state.language))
                            legendItem(color: .green, text: I18n.localized("log_phase_resting", language: state.language))
                            legendItem(color: .teal, text: I18n.localized("log_phase_breathing", language: state.language))
                            legendItem(color: .gray.opacity(0.5), text: I18n.localized("log_phase_idle", language: state.language))
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }

                    // 2. Summary Statistics
                    VStack(spacing: 16) {
                        summaryRow(title: I18n.localized("log_duration_working", language: state.language), duration: totalWorkDuration, color: .blue)
                        summaryRow(title: I18n.localized("log_duration_overworking", language: state.language), duration: totalOverworkingDuration, color: .red)
                        summaryRow(title: I18n.localized("log_duration_resting", language: state.language), duration: totalRestDuration, color: .green)
                        summaryRow(title: I18n.localized("log_duration_breathing", language: state.language), duration: totalBreathingDuration, color: .teal)
                        summaryRow(title: I18n.localized("log_duration_idle", language: state.language), duration: totalIdleDuration, color: .gray)
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)

                    // 3. Detailed Records — custom full-row tappable header
                    VStack(spacing: 0) {
                        // Header row: entire row is tappable
                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                isDetailExpanded.toggle()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .rotationEffect(.degrees(isDetailExpanded ? 90 : 0))
                                    .animation(.easeInOut(duration: 0.2), value: isDetailExpanded)
                                Text(I18n.localized("log_view_details", language: state.language))
                                    .font(.body)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .padding()
                        }
                        .buttonStyle(.plain)

                        // Expanded content
                        if isDetailExpanded {
                            VStack(spacing: 12) {
                                ForEach(visibleLogs.reversed()) { log in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(timeRangeString(for: log))
                                                .font(.system(.subheadline, design: .monospaced))
                                                .foregroundColor(.secondary)
                                        }

                                        Spacer()

                                        HStack(spacing: 6) {
                                            Text(icon(for: log.phase))
                                            Text(name(for: log.phase))
                                                .font(.subheadline.bold())
                                        }

                                        Text(durationString(for: log))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .frame(width: 80, alignment: .trailing)
                                    }
                                    if log != visibleLogs.first {
                                        Divider()
                                    }
                                }
                            }
                            .padding([.horizontal, .bottom])
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    .cornerRadius(12)
                }
                .padding(24)
            }
        }
    }

    private func width(for log: SessionLog, in totalWidth: CGFloat) -> CGFloat {
        guard totalDuration > 0 else { return 0 }
        let duration = logDuration(log)
        return totalWidth * CGFloat(duration / totalDuration)
    }

    private func color(for phase: AppPhase) -> Color {
        switch phase {
        case .working: return .blue
        case .resting: return .green
        case .overworking: return .red
        case .breathing: return .teal
        default: return .gray.opacity(0.5)
        }
    }

    private func legendItem(color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(text)
        }
    }

    private func summaryRow(title: String, duration: TimeInterval, color: Color) -> some View {
        HStack {
            legendItem(color: color, text: title)
                .font(.body)
            Spacer()
            Text(format(duration: duration))
                .font(.system(.body, design: .monospaced).bold())
        }
    }

    private func format(duration: TimeInterval) -> String {
        let minutes = Int(duration / 60)
        let hourLabel = I18n.localized("unit_hours_label", language: state.language)
        let minuteLabel = I18n.localized("unit_minutes_label", language: state.language)

        if minutes >= 60 {
            let hours = minutes / 60
            let mins = minutes % 60
            return "\(hours)\(hourLabel) \(mins)\(minuteLabel)"
        } else {
            return "\(minutes)\(minuteLabel)"
        }
    }

    private func timeRangeString(for log: SessionLog) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let start = formatter.string(from: log.startTime)
        let end = log.endTime.map { formatter.string(from: $0) } ?? (state.language == .zhHans ? "至今" : "Now")
        return "\(start) – \(end)"
    }

    private func icon(for phase: AppPhase) -> String {
        switch phase {
        case .working: return "💻"
        case .resting: return "☕️"
        case .overworking: return "🔥"
        case .breathing: return "🫁"
        case .idle: return "🌙"
        case .paused: return "⏸️"
        case .alerting: return "⚠️"
        }
    }

    private func name(for phase: AppPhase) -> String {
        switch phase {
        case .working: return I18n.localized("log_phase_working", language: state.language)
        case .resting: return I18n.localized("log_phase_resting", language: state.language)
        case .overworking: return I18n.localized("log_phase_overworking", language: state.language)
        case .breathing: return I18n.localized("log_phase_breathing", language: state.language)
        case .idle: return I18n.localized("log_phase_idle", language: state.language)
        case .paused: return I18n.localized("menu_pause", language: state.language)
        case .alerting: return "Alerting"
        }
    }

    private func durationString(for log: SessionLog) -> String {
        format(duration: logDuration(log))
    }
}
