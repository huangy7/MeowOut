import SwiftUI

/// 托盘快捷工具卡内条件展开的防休眠时长与合盖控制区。
struct KeepAwakeDurationBar: View {
    let language: AppState.AppLanguage
    @ObservedObject private var power = PowerAssertionService.shared
    @State private var untilDraft: Date?

    private var untilSelection: Binding<Date> {
        Binding(
            get: {
                if let untilDraft {
                    return untilDraft
                }
                if power.savedUntilTime > 0 {
                    return Date(timeIntervalSinceReferenceDate: power.savedUntilTime)
                }
                return Date().addingTimeInterval(3600)
            },
            set: { untilDraft = $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
                .background(Color.primary.opacity(0.06))

            // 第一行：实时状态 / 低电量提示 + 快捷续时芯片
            TimelineView(.periodic(from: .now, by: power.isKeepingAwake && power.endDate != nil ? 1 : 30)) { context in
                if let blockedPercent = power.batteryProtectionPercent() {
                    HStack(alignment: .top, spacing: 5) {
                        Image(systemName: "battery.25")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.orange)
                            .padding(.top, 1)
                        Text(I18n.localizedFormat("power_battery_blocked_format", language: language, blockedPercent))
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.12))
                    .cornerRadius(7)
                } else {
                    HStack(spacing: 4) {
                        statusText(now: context.date)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .lineLimit(1)

                        Spacer(minLength: 4)

                        if power.isKeepingAwake, power.endDate != nil {
                            HStack(spacing: 4) {
                                ForEach(KeepAwakeSupport.extendMinutes, id: \.self) { minutes in
                                    Button("+" + KeepAwakeSupport.shortChipTitle(for: minutes, language: language)) {
                                        power.extend(minutes: minutes)
                                    }
                                    .buttonStyle(KeepAwakeExtendChipStyle())
                                }
                            }
                        }
                    }
                    .frame(minHeight: 20)
                }
            }

            // 第二行：2x4 时长胶囊芯片网格
            VStack(spacing: 5) {
                HStack(spacing: 5) {
                    ForEach(Array(KeepAwakeSupport.presetMinutes.prefix(4)), id: \.self) { minutes in
                        durationChip(minutes)
                    }
                }
                HStack(spacing: 5) {
                    ForEach(Array(KeepAwakeSupport.presetMinutes.dropFirst(4)), id: \.self) { minutes in
                        durationChip(minutes)
                    }
                    KeepAwakeEndTimePicker(
                        language: language,
                        selection: untilSelection,
                        activeEnd: power.isKeepingAwake && power.sessionMinutes == nil ? power.endDate : nil,
                        onStop: { power.toggle() },
                        onStart: {
                            let resolved = KeepAwakeSupport.resolvedUntilDate(
                                picked: untilSelection.wrappedValue,
                                now: Date()
                            )
                            power.activate(until: resolved)
                            untilDraft = nil
                        }
                    )
                }
            }

            // 第三行：合盖不休眠快捷开关（与设置页双向同步）
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(I18n.localized("power_clamshell_title", language: language))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(power.clamshellStatusCaption(language: language))
                        .font(.system(size: 9.5))
                        .foregroundStyle(power.clamshellSetupFailed ? Color.red : Color.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Toggle("", isOn: $power.clamshellPreferred)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .disabled(power.clamshellSetupInProgress)
            }
            .padding(.top, 2)
        }
    }

    @ViewBuilder
    private func statusText(now: Date) -> some View {
        if power.isKeepingAwake {
            if let end = power.endDate {
                let remaining = KeepAwakeSupport.remainingStatusText(remaining: end.timeIntervalSince(now))
                Text(I18n.localizedFormat("keep_awake_remaining_status_format", language: language, remaining))
            } else {
                Text(I18n.localized("keep_awake_status_indefinite", language: language))
            }
        } else {
            Text(I18n.localized("keep_awake_status_idle_hint", language: language))
        }
    }

    private func durationChip(_ minutes: Int) -> some View {
        let isSelected = power.isKeepingAwake && power.sessionMinutes == minutes
        return Button {
            if isSelected {
                power.toggle()
            } else {
                power.activate(minutes: minutes)
            }
        } label: {
            Text(KeepAwakeSupport.shortChipTitle(for: minutes, language: language))
        }
        .buttonStyle(KeepAwakeChipStyle(isSelected: isSelected))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// 防休眠时长预设与「直到…」通用胶囊样式。
struct KeepAwakeChipStyle: ButtonStyle {
    var isSelected: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10.5, weight: .medium))
            .monospacedDigit()
            .lineLimit(1)
            .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.88))
            .padding(.horizontal, 5)
            .frame(maxWidth: .infinity)
            .frame(height: 23)
            .background(
                Capsule().fill(
                    isSelected
                        ? Color.orange.opacity(configuration.isPressed ? 0.8 : 1.0)
                        : Color.primary.opacity(configuration.isPressed ? 0.14 : 0.07)
                )
            )
            .contentShape(Capsule())
    }
}

/// 定时运行中的快捷续时胶囊样式（+15m / +30m / +1h）。
private struct KeepAwakeExtendChipStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .semibold))
            .monospacedDigit()
            .lineLimit(1)
            .foregroundStyle(Color.orange)
            .padding(.horizontal, 6)
            .frame(height: 20)
            .background(
                Capsule().fill(Color.orange.opacity(configuration.isPressed ? 0.24 : 0.14))
            )
            .contentShape(Capsule())
    }
}
