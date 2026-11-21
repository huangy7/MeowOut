import Foundation

/// 防休眠时长、倒计时格式化与合盖补休眠判定纯逻辑（零系统副作用，便于单测）。
public enum KeepAwakeSupport {
    /// 预设时长（分钟），0 表示持续保持唤醒（永久）。
    public static let presetMinutes: [Int] = [15, 30, 60, 120, 240, 480, 0]

    /// 快捷续时档位（分钟）。
    public static let extendMinutes: [Int] = [15, 30, 60]

    /// 清洗持久化或外部传入的预设时长，非法值回退为 0（永久）。
    public static func sanitizedDuration(_ minutes: Int) -> Int {
        presetMinutes.contains(minutes) ? minutes : 0
    }

    /// 将选中的时分映射到下一个未来时刻；今日已过（含与当前时刻相同）则自动顺延至明日。
    public static func resolvedUntilDate(
        picked: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date {
        let components = calendar.dateComponents([.hour, .minute], from: picked)
        guard let candidate = calendar.nextDate(
            after: now.addingTimeInterval(-60),
            matching: components,
            matchingPolicy: .nextTime
        ) else {
            return picked
        }
        if candidate > now {
            return candidate
        }
        return calendar.date(byAdding: .day, value: 1, to: candidate)
            ?? candidate.addingTimeInterval(24 * 3600)
    }

    /// 磁贴紧凑倒计时文案，如 "59:42" 或 "1:05:12"。
    public static func countdownText(remaining: TimeInterval) -> String {
        let total = max(0, Int(remaining))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// 状态行可读剩余时长，如 "1h 05m"、"30m 05s"、"42s"。
    public static func remainingStatusText(remaining: TimeInterval) -> String {
        let total = max(0, Int(remaining))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%dh %02dm", hours, minutes)
        }
        if minutes > 0 {
            return String(format: "%dm %02ds", minutes, seconds)
        }
        return "\(seconds)s"
    }

    /// 短标签文案（用于芯片展示）。
    public static func shortChipTitle(for minutes: Int, language: AppState.AppLanguage) -> String {
        switch minutes {
        case 0:
            return I18n.localized("keep_awake_indefinite", language: language)
        case 15:
            return "15m"
        case 30:
            return "30m"
        case 60:
            return "1h"
        case 120:
            return "2h"
        case 240:
            return "4h"
        case 480:
            return "8h"
        default:
            return "\(minutes)m"
        }
    }

    /// 判定在已合盖状态下，系统及其他进程是否允许主动触发合盖休眠。
    /// - 接电且连有外接显示器（标准合盖桌面模式）时不强制休眠。
    /// - 存在活跃的合盖级 assertion（AppliesOnLidClose / ProcessingHotPlug）时不强制休眠。
    /// - 普通空闲休眠 assertion 或已释放的 assertion（AssertLevel == 0）不阻止。
    public static func lidSleepIsAllowed(
        systemAllowsSleep: Bool?,
        externalDisplayConnected: Bool?,
        connectedToPower: Bool?,
        assertions: [[String: Any]]?
    ) -> Bool {
        guard systemAllowsSleep == true,
              let assertions,
              connectedToPower == false || externalDisplayConnected == false else {
            return false
        }

        return !assertions.contains { assertion in
            switch assertion["AssertType"] as? String {
            case "UserIsActive", "DisplayWake", "PreventSystemSleep", nil:
                break
            default:
                return false
            }

            let appliesToLid = (assertion["AppliesOnLidClose"] as? Bool == true)
                || (assertion["ProcessingHotPlug"] as? Bool == true)
            let isActiveLevel = (assertion["AssertLevel"] as? Int) != 0
            return appliesToLid && isActiveLevel
        }
    }

    /// 给定在线显示器的内置标志列表，判断是否存在外接显示器。
    public static func hasExternalDisplay(builtInFlags: [Bool]) -> Bool {
        builtInFlags.contains(false)
    }
}

/// Sudoers 规则与 `pmset -g` 解析纯逻辑。
public enum SudoersSupport {
    /// `pmset -g` 输出中是否存在 `SleepDisabled 1`。
    public static func sleepDisabled(inPmsetOutput output: String) -> Bool {
        output.range(of: #"SleepDisabled\s+1"#, options: .regularExpression) != nil
    }

    /// 生成基于数字 UID 的受限 NOPASSWD 规则，规避特殊用户名（如企业 SSO 邮箱短名）问题。
    public static func clamshellRule(uid: uid_t) -> String {
        "#\(uid) ALL=(root) NOPASSWD: /usr/bin/pmset disablesleep 1, /usr/bin/pmset disablesleep 0"
    }
}
