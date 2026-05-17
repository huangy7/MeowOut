import SwiftUI

struct TodayReviewView: View {
    let logs: [SessionLog]
    @State private var isDetailExpanded = false
    
    // Helpers to calculate durations
    private var totalDuration: TimeInterval {
        guard let first = logs.first else { return 0 }
        return Date().timeIntervalSince(first.startTime)
    }
    
    private var totalWorkDuration: TimeInterval {
        logs.filter { $0.phase == .working }.reduce(0) { total, log in
            total + (log.endTime ?? Date()).timeIntervalSince(log.startTime)
        }
    }
    
    private var totalRestDuration: TimeInterval {
        logs.filter { $0.phase == .resting }.reduce(0) { total, log in
            total + (log.endTime ?? Date()).timeIntervalSince(log.startTime)
        }
    }
    
    private var totalIdleDuration: TimeInterval {
        logs.filter { $0.phase == .idle || $0.phase == .paused || $0.phase == .alerting }.reduce(0) { total, log in
            total + (log.endTime ?? Date()).timeIntervalSince(log.startTime)
        }
    }

    var body: some View {
        if logs.isEmpty {
            Text("暂无记录").foregroundColor(.secondary).padding()
        } else {
            ScrollView { // Use ScrollView to handle expanded content
                VStack(spacing: 30) {
                    // 1. Timeline Bar
                    VStack(alignment: .leading, spacing: 8) {
                        Text("今日时间轴")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
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
                            legendItem(color: .blue, text: "工作")
                            legendItem(color: .green, text: "休息")
                            legendItem(color: .gray.opacity(0.5), text: "离开/其他")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                    }
                    
                    // 2. Summary Statistics
                    VStack(spacing: 16) {
                        summaryRow(title: "总工作", duration: totalWorkDuration, color: .blue)
                        summaryRow(title: "总休息", duration: totalRestDuration, color: .green)
                        summaryRow(title: "总离开", duration: totalIdleDuration, color: .gray)
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)
                    
                    // 3. Detailed Records (DisclosureGroup)
                    DisclosureGroup("查看详细记录", isExpanded: $isDetailExpanded) {
                        VStack(spacing: 12) {
                            ForEach(logs.reversed()) { log in // Show newest first
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
                                if log != logs.first {
                                    Divider()
                                }
                            }
                        }
                        .padding(.top, 12)
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    .cornerRadius(12)
                }
                .padding(24)
            }
        }
    }
    
    private func width(for log: SessionLog, in totalWidth: CGFloat) -> CGFloat {
        guard totalDuration > 0 else { return 0 }
        let duration = (log.endTime ?? Date()).timeIntervalSince(log.startTime)
        return totalWidth * CGFloat(duration / totalDuration)
    }
    
    private func color(for phase: AppPhase) -> Color {
        switch phase {
        case .working: return .blue
        case .resting: return .green
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
        if minutes >= 60 {
            let hours = minutes / 60
            let mins = minutes % 60
            return "\(hours)小时 \(mins)分钟"
        } else {
            return "\(minutes)分钟"
        }
    }

    private func timeRangeString(for log: SessionLog) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let start = formatter.string(from: log.startTime)
        let end = log.endTime.map { formatter.string(from: $0) } ?? "至今"
        return "\(start) - \(end)"
    }

    private func icon(for phase: AppPhase) -> String {
        switch phase {
        case .working: return "💻"
        case .resting: return "☕️"
        case .idle: return "🌙"
        case .paused: return "⏸️"
        case .alerting: return "⚠️"
        }
    }

    private func name(for phase: AppPhase) -> String {
        switch phase {
        case .working: return "工作"
        case .resting: return "休息"
        case .idle: return "离开"
        case .paused: return "暂停"
        case .alerting: return "提醒"
        }
    }

    private func durationString(for log: SessionLog) -> String {
        let duration = (log.endTime ?? Date()).timeIntervalSince(log.startTime)
        return format(duration: duration)
    }
}
