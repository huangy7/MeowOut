import AppKit
import SwiftUI

/// 「直到…」指定结束时刻胶囊芯片与弹出选择器。
/// 支持直接键入时间、双列滚轮滚动、点击相邻数字和键盘上下箭头微调。
struct KeepAwakeEndTimePicker: View {
    let language: AppState.AppLanguage
    @Binding var selection: Date
    var activeEnd: Date?
    var onStop: () -> Void
    var onStart: () -> Void

    @State private var isPresented = false

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    var body: some View {
        Button {
            if activeEnd != nil {
                onStop()
            } else {
                isPresented.toggle()
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "clock")
                    .font(.system(size: 9.5, weight: .semibold))
                if let activeEnd {
                    Text(Self.timeFormatter.string(from: activeEnd))
                } else {
                    Text(I18n.localized("keep_awake_until_chip", language: language))
                }
            }
        }
        .buttonStyle(KeepAwakeChipStyle(isSelected: activeEnd != nil))
        .accessibilityLabel(I18n.localized("keep_awake_until_label", language: language))
        .accessibilityValue(activeEnd.map { Self.timeFormatter.string(from: $0) } ?? "")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            editor
        }
    }

    private var editor: some View {
        VStack(spacing: 10) {
            HStack {
                Text(I18n.localized("keep_awake_until_label", language: language))
                    .font(.system(size: 11.5, weight: .semibold))
                Spacer()
                DatePicker(
                    I18n.localized("keep_awake_until_label", language: language),
                    selection: $selection,
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.field)
                .controlSize(.small)
                .labelsHidden()
                .fixedSize()
            }

            HStack(spacing: 6) {
                KeepAwakeTimeDigitWheel(
                    title: I18n.localized("keep_awake_hour_label", language: language),
                    range: 24,
                    value: part(.hour)
                )
                Text(":")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.tertiary)
                KeepAwakeTimeDigitWheel(
                    title: I18n.localized("keep_awake_minute_label", language: language),
                    range: 60,
                    value: part(.minute)
                )
            }

            Divider()

            HStack {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(endSummary(now: context.date))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer()
                Button(I18n.localized("keep_awake_until_start", language: language)) {
                    isPresented = false
                    onStart()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.small)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .frame(width: 224)
    }

    private func part(_ component: Calendar.Component) -> Binding<Int> {
        Binding(
            get: { Calendar.current.component(component, from: selection) },
            set: { value in
                var parts = Calendar.current.dateComponents([.hour, .minute], from: selection)
                parts.setValue(value, for: component)
                parts.year = 2001
                parts.month = 1
                parts.day = 15
                if let date = Calendar.current.date(from: parts) {
                    selection = date
                }
            }
        )
    }

    private func endSummary(now: Date) -> String {
        let calendar = Calendar.current
        let end = KeepAwakeSupport.resolvedUntilDate(picked: selection, now: now, calendar: calendar)
        let isToday = calendar.isDate(end, inSameDayAs: now)
        let dayText = I18n.localized(isToday ? "keep_awake_until_today" : "keep_awake_until_tomorrow", language: language)
        let remaining = KeepAwakeSupport.remainingStatusText(remaining: max(60, end.timeIntervalSince(now)))
        return "\(dayText) · \(remaining)"
    }
}

/// 可滚动、可点击、支持方向键的双位数字时间滚轮列。
private struct KeepAwakeTimeDigitWheel: View {
    let title: String
    let range: Int
    @Binding var value: Int

    @State private var hovering = false
    @State private var monitor: Any?
    @State private var accumulated: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            neighbour(-1)
            Text(String(format: "%02d", value))
                .font(.system(size: 24, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Color.orange)
                .frame(width: 52, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.orange.opacity(hovering ? 0.22 : 0.14))
                )
            neighbour(1)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .focusable()
        .onKeyPress(.upArrow) {
            step(-1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            step(1)
            return .handled
        }
        .onAppear(perform: installMonitor)
        .onDisappear {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }
        .accessibilityElement()
        .accessibilityLabel(title)
        .accessibilityValue(String(format: "%02d", value))
        .accessibilityAdjustableAction { direction in
            step(direction == .increment ? 1 : -1)
        }
    }

    private func neighbour(_ offset: Int) -> some View {
        Text(String(format: "%02d", wrapped(value + offset)))
            .font(.system(size: 12))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .frame(width: 52, height: 20)
            .contentShape(Rectangle())
            .onTapGesture { step(offset) }
    }

    private func step(_ delta: Int) {
        value = wrapped(value + delta)
    }

    private func wrapped(_ n: Int) -> Int {
        (n % range + range) % range
    }

    private func installMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard hovering else { return event }
            guard event.momentumPhase.isEmpty else { return nil }
            let threshold: CGFloat = event.hasPreciseScrollingDeltas ? 8 : 1
            accumulated += event.scrollingDeltaY
            while abs(accumulated) >= threshold {
                step(accumulated < 0 ? 1 : -1)
                accumulated += accumulated < 0 ? threshold : -threshold
            }
            return nil
        }
    }
}
