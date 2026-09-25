import SwiftUI
import AppKit

public struct SystemMonitorCardView: View {
    @ObservedObject private var metrics = SystemMetricsService.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppState.self) private var envAppState: AppState?
    
    public var appState: AppState?
    @State private var expanded: BreakdownKind? = nil

    public init(appState: AppState? = nil) {
        self.appState = appState
    }

    private var effectiveAppState: AppState? {
        appState ?? envAppState
    }

    /// 传给 I18n 的语言代码：.system 必须解析为真实语言（rawValue "system" 不是合法 languageCode）
    var language: String {
        guard let appLanguage = effectiveAppState?.language else { return "zh-Hans" }
        return I18n.resolveLanguage(appLanguage)
    }

    public static func toggleBreakdown(kind: BreakdownKind, current: inout BreakdownKind?) {
        if current == kind {
            current = nil
        } else {
            current = kind
        }
    }

    public static func calculatePeak(downHistory: [Double], upHistory: [Double], minPeak: Double = 1024) -> Double {
        let safeMin = (minPeak.isFinite && minPeak >= 0) ? minPeak : 1024.0
        let downMax = downHistory.compactMap { $0.isFinite ? max(0.0, $0) : nil }.max() ?? 0.0
        let upMax = upHistory.compactMap { $0.isFinite ? max(0.0, $0) : nil }.max() ?? 0.0
        return max(downMax, upMax, safeMin)
    }

    /// 容量条按占用率分档着色：接近写满时用红色直接给出告警，
    /// 让「磁盘快满了」不需要读数字也能看出来
    public static func diskBarColor(fraction: Double) -> Color {
        guard fraction.isFinite else { return .green }
        if fraction >= 0.90 { return .red }
        if fraction >= 0.75 { return .orange }
        return .green
    }

    public static func batterySymbolName(chargePercent: Int?, isCharging: Bool, externalConnected: Bool) -> String {
        let percent = chargePercent ?? 0
        let tier: String
        if percent >= 88 {
            tier = "100"
        } else if percent >= 60 {
            tier = "75"
        } else if percent >= 35 {
            tier = "50"
        } else if percent >= 13 {
            tier = "25"
        } else {
            tier = "0"
        }
        if isCharging {
            return "battery.\(tier).bolt"
        } else {
            return "battery.\(tier)"
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: Title & Uptime Badge
            HStack(alignment: .center, spacing: 6) {
                Text("💻")
                    .font(.system(size: 13))
                Text(I18n.localized("system_status_title", language: language))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.primary)

                Spacer()

                // Uptime Badge
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 5, height: 5)
                    Text(SystemMetricsService.formatUptime(seconds: metrics.snapshot.uptimeSeconds, language: language))
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(.green)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 2.5)
                .background(Color.green.opacity(0.12))
                .cornerRadius(999)
            }

            // CPU Row
            VStack(alignment: .leading, spacing: 6) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        Self.toggleBreakdown(kind: .cpu, current: &expanded)
                    }
                    if expanded == .cpu {
                        metrics.refreshTopProcesses(kind: .cpu)
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: expanded == .cpu ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.secondary)
                            .frame(width: 10)

                        Text(I18n.localized("system_cpu_label", language: language))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.primary.opacity(0.85))

                        Spacer()

                        Text(String(format: "%.1f%%", metrics.snapshot.cpuUsage * 100))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(.blue)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // CPU Top 5 Process List
                if expanded == .cpu {
                    processListView(items: metrics.topCPUProcesses, isCPU: true)
                }
            }

            Divider().background(Color.primary.opacity(0.05))

            // Memory Row
            VStack(alignment: .leading, spacing: 6) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        Self.toggleBreakdown(kind: .memory, current: &expanded)
                    }
                    if expanded == .memory {
                        metrics.refreshTopProcesses(kind: .memory)
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: expanded == .memory ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.secondary)
                            .frame(width: 10)

                        Text(I18n.localized("system_mem_label", language: language))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.primary.opacity(0.85))

                        Spacer()

                        Text("\(SystemMetricsService.formatBytes(metrics.snapshot.memoryUsed)) / \(SystemMetricsService.formatBytes(metrics.snapshot.memoryTotal))")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(.orange)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // Memory Top 5 Process List
                if expanded == .memory {
                    processListView(items: metrics.topMemoryProcesses, isCPU: false)
                }
            }

            // 容量不可读时整行隐藏，而不是显示 0 GB / 0 GB
            if let disk = metrics.snapshot.disk {
                Divider().background(Color.primary.opacity(0.05))

                // Disk Row
                VStack(alignment: .leading, spacing: 6) {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            Self.toggleBreakdown(kind: .disk, current: &expanded)
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: expanded == .disk ? "chevron.down" : "chevron.right")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.secondary)
                                .frame(width: 10)

                            Text(I18n.localized("system_disk_label", language: language))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.primary.opacity(0.85))

                            Spacer()

                            Text("\(SystemMetricsService.formatDiskBytes(disk.usedBytes)) / \(SystemMetricsService.formatDiskBytes(disk.totalBytes))")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(.purple)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if expanded == .disk {
                        diskDetailView(disk: disk)
                    }
                }
            }

            Divider().background(Color.primary.opacity(0.05))

            // Network Row
            VStack(alignment: .leading, spacing: 6) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        Self.toggleBreakdown(kind: .network, current: &expanded)
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: expanded == .network ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.secondary)
                            .frame(width: 10)

                        Text(I18n.localized("system_net_label", language: language))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.primary.opacity(0.85))

                        Spacer()

                        HStack(spacing: 8) {
                            HStack(spacing: 2) {
                                Text("↓")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.blue)
                                Text(SystemMetricsService.formatSpeed(metrics.snapshot.netDownBytesPerSec))
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundColor(.primary.opacity(0.85))
                            }

                            HStack(spacing: 2) {
                                Text("↑")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.green)
                                Text(SystemMetricsService.formatSpeed(metrics.snapshot.netUpBytesPerSec))
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundColor(.primary.opacity(0.85))
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if expanded == .network {
                    networkSparklineView
                }
            }

            if metrics.snapshot.battery.hasBattery {
                Divider().background(Color.primary.opacity(0.05))

                batteryRow

                if expanded == .battery {
                    batteryDetailView
                }
            }
        }
        .padding(12)
        .menuCardStyle()
        .onAppear {
            metrics.start()
        }
        .onDisappear {
            metrics.stop()
            expanded = nil
        }
        .onReceive(metrics.$snapshot) { _ in
            guard let currentExpanded = expanded else { return }
            switch currentExpanded {
            case .cpu, .memory, .battery:
                metrics.refreshTopProcesses(kind: currentExpanded)
            case .network, .disk:
                break
            }
        }
    }

    @ViewBuilder
    private func diskDetailView(disk: DiskReading) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(disk.volumeName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                HStack(spacing: 4) {
                    // 文件系统类型取自挂载表，理论上可能为空，空串不占位
                    if !disk.fileSystem.isEmpty {
                        diskTag(disk.fileSystem)
                    }
                    diskTag(I18n.localized(disk.isInternal ? "system_disk_internal" : "system_disk_external",
                                           language: language))
                }
            }

            HStack(spacing: 6) {
                diskCapacityBar(fraction: disk.usedFraction)

                Text(String(format: "%.0f%%", disk.usedFraction * 100))
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 6) {
                Text("\(SystemMetricsService.formatDiskBytes(disk.availableBytes)) \(I18n.localized("system_disk_available", language: language))")
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)

                Spacer()

                // 可清除量为 0 时没有可清理空间，「0 GB 可清除」只是噪音
                if disk.purgeableBytes > 0 {
                    Text("\(SystemMetricsService.formatDiskBytes(disk.purgeableBytes)) \(I18n.localized("system_disk_purgeable", language: language))")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(8)
        .background(
            colorScheme == .dark
                ? Color.white.opacity(0.04)
                : Color.black.opacity(0.02)
        )
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.04), lineWidth: 0.5)
        )
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    @ViewBuilder
    private func diskCapacityBar(fraction: Double) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.12))

                Capsule()
                    .fill(Self.diskBarColor(fraction: fraction))
                    .frame(width: geometry.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 6)
    }

    @ViewBuilder
    private func diskTag(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .foregroundColor(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(Color.primary.opacity(0.06))
            .cornerRadius(999)
    }

    @ViewBuilder
    private func processListView(items: [ProcessUsageItem], isCPU: Bool) -> some View {
        VStack(spacing: 3) {
            if items.isEmpty && metrics.isSamplingProcesses {
                HStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(height: 20)
                    Spacer()
                }
            } else {
                ForEach(items.prefix(5)) { item in
                    ProcessItemRow(item: item, isCPU: isCPU)
                }
            }
        }
        .padding(.top, 4)
        .padding(.horizontal, 2)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    @ViewBuilder
    private var networkSparklineView: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(I18n.localized("system_net_history", language: language))
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundColor(.secondary)

                Spacer()

                HStack(spacing: 6) {
                    HStack(spacing: 2) {
                        Circle().fill(Color.blue).frame(width: 4.5, height: 4.5)
                        Text(I18n.localized("system_net_download", language: language))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                    }

                    HStack(spacing: 2) {
                        Circle().fill(Color.green).frame(width: 4.5, height: 4.5)
                        Text(I18n.localized("system_net_upload", language: language))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
            }

            let down = metrics.snapshot.netDownHistory
            let up = metrics.snapshot.netUpHistory
            let peak = Self.calculatePeak(downHistory: down, upHistory: up)

            ZStack {
                Sparkline(values: down, color: .blue, maxValue: peak, fillOpacity: 0.15, lineWidth: 1.5, showsZeroBaseline: true)
                Sparkline(values: up, color: .green, maxValue: peak, fillOpacity: 0.0, lineWidth: 1.3)
            }
            .frame(height: 32)
            .padding(.vertical, 2)
        }
        .padding(8)
        .background(
            colorScheme == .dark
                ? Color.white.opacity(0.04)
                : Color.black.opacity(0.02)
        )
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.04), lineWidth: 0.5)
        )
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    @ViewBuilder
    private var batteryRow: some View {
        let battery = metrics.snapshot.battery
        let charge = battery.chargePercent ?? 0

        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                Self.toggleBreakdown(kind: .battery, current: &expanded)
            }
            if expanded == .battery {
                metrics.refreshTopProcesses(kind: .battery)
            }
        }) {
            HStack(spacing: 4) {
                Image(systemName: expanded == .battery ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 10)

                Text(I18n.localized("system_battery_label", language: language))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary.opacity(0.85))

                Spacer()

                HStack(spacing: 3) {
                    if battery.isCharging {
                        Text("⚡")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                    }
                    Text("\(charge)%")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary.opacity(0.85))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var batteryDetailView: some View {
        let battery = metrics.snapshot.battery
        let healthText = battery.healthPercent.map { String(format: "%.1f%%", $0) } ?? "--"
        let cyclesText = battery.cycleCount.map(String.init) ?? "--"

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(I18n.localized("system_battery_health", language: language))
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(.secondary)
                    Text(healthText)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.primary.opacity(0.9))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(I18n.localized("system_battery_cycles", language: language))
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(.secondary)
                    Text(cyclesText)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.primary.opacity(0.9))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()
                .opacity(0.25)

            VStack(alignment: .leading, spacing: 4) {
                Text(I18n.localized("system_battery_energy_title", language: language))
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundColor(.secondary)

                if metrics.topEnergyProcesses.isEmpty && metrics.isSamplingProcesses {
                    HStack {
                        Spacer()
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(height: 18)
                        Spacer()
                    }
                } else if metrics.topEnergyProcesses.isEmpty {
                    Text(I18n.localized("system_battery_energy_idle", language: language))
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary.opacity(0.8))
                        .padding(.vertical, 2)
                } else {
                    VStack(spacing: 3) {
                        ForEach(metrics.topEnergyProcesses.prefix(5)) { item in
                            ProcessItemRow(item: item, isCPU: true)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(
            colorScheme == .dark
                ? Color.white.opacity(0.04)
                : Color.black.opacity(0.02)
        )
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.04), lineWidth: 0.5)
        )
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

// MARK: - Clickable Process Item Row
private struct ProcessItemRow: View {
    let item: ProcessUsageItem
    let isCPU: Bool
    @State private var isHovered = false

    var body: some View {
        Group {
            if item.canActivate {
                Button(action: {
                    item.activate()
                }) {
                    rowContent
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    isHovered = hovering
                }
            } else {
                rowContent
            }
        }
        .help(item.name)
    }

    private var rowContent: some View {
        HStack(spacing: 6) {
            if let icon = item.icon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 13, height: 13)
                    .cornerRadius(3)
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: 10))
                    .frame(width: 13, height: 13)
                    .foregroundColor(.secondary)
            }

            Text(item.name)
                .font(.system(size: 11))
                .foregroundColor(.primary.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            Text(isCPU ? String(format: "%.1f%%", item.cpuPercent) : SystemMetricsService.formatBytes(item.memoryBytes))
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 2.5)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovered && item.canActivate ? Color.primary.opacity(0.06) : Color.clear)
        )
        .contentShape(Rectangle())
    }
}

