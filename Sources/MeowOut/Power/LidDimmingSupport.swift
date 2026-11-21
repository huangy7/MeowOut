import Foundation

/// 合盖自动暗屏动作决策纯逻辑（零硬件依赖，便于单元测试）。
public enum LidDimmingSupport {
    public enum Action: Equatable {
        /// 持久化原亮度并将内置屏亮度降为 0。
        case dim(save: Double)
        /// 将内置屏亮度恢复为指定值，并在写入成功后清除持久化标记。
        case restore(Double)
        case none
    }

    /// 盖子合上时触发决策。
    /// 若读取到的亮度为 nil 或 <= 0（面板已熄屏），返回 .none，避免误存 0 导致开盖后变黑屏。
    public static func lidClosed(currentBrightness: Double?) -> Action {
        guard let currentBrightness, currentBrightness > 0 else { return .none }
        return .dim(save: currentBrightness)
    }

    /// 开盖、关闭暗屏选项、会话结束或启动崩溃恢复时的决策。
    public static func restoring(saved: Double?) -> Action {
        guard let saved else { return .none }
        return .restore(saved)
    }
}
