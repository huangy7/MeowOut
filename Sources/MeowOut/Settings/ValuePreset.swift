import Foundation

/// 数值设置的预设档位配置与自定义值处理逻辑（纯逻辑，供 PresetValueRow 使用）
struct ValuePreset: Equatable {
    let range: ClosedRange<Int>
    let step: Int
    let presets: [Int]

    /// 将任意输入值夹取到范围内并按步进向下对齐
    func snapped(_ value: Int) -> Int {
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        let steps = (clamped - range.lowerBound) / step
        return range.lowerBound + steps * step
    }

    /// 当前值是否为预设档位
    func isPreset(_ value: Int) -> Bool {
        presets.contains(value)
    }

    /// 菜单展示的完整档位：预设有序列表；当前值非预设时插入对齐后的当前值（保持有序）
    func menuValues(currentValue: Int) -> [Int] {
        let v = snapped(currentValue)
        if presets.contains(v) { return presets }
        return (presets + [v]).sorted()
    }
}

extension ValuePreset {
    static let workDuration = ValuePreset(range: 15...120, step: 5, presets: [15, 25, 30, 45, 60, 90, 120])
    static let restDuration = ValuePreset(range: 1...30, step: 1, presets: [1, 2, 5, 10, 15, 20, 30])
    static let alertBefore = ValuePreset(range: 1...15, step: 1, presets: [1, 2, 3, 5, 10])
    static let restToReset = ValuePreset(range: 2...30, step: 1, presets: [2, 5, 10, 15, 20, 30])
    static let dailyWorkGoal = ValuePreset(range: 4...12, step: 1, presets: [4, 6, 8, 10, 12])
    static let dailyWaterGoal = ValuePreset(range: 4...20, step: 1, presets: [4, 6, 8, 10, 12, 16, 20])
    static let waterInterval = ValuePreset(range: 15...120, step: 5, presets: [15, 30, 45, 60, 90, 120])
    /// 电池保护阈值：0 表示关闭
    static let batteryThreshold = ValuePreset(range: 0...50, step: 5, presets: [0, 10, 20, 30, 40, 50])
}
