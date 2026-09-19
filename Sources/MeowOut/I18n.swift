import Foundation

/// 强制资源管理器：确保在不同环境下都能正确加载到语言包
public final class I18n {
    /// 兼容性 Bundle 访问器
    private static var bundle: Bundle {
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        // 在 Xcode 环境下，资源通常在主 Bundle 或与类关联的 Bundle 中
        return Bundle(for: I18n.self)
        #endif
    }

    /// 内置静态词条字典（支持多语言快速检索与兜底）
    private static let systemMonitorDictionary: [String: [String: String]] = [
        "zh-Hans": [
            "system_status_title": "系统状态",
            "system_cpu_label": "CPU",
            "system_mem_label": "内存",
            "system_net_label": "网络",
            "system_net_history": "实时速率走势 (最近 30 秒)",
            "system_net_download": "下载",
            "system_net_upload": "上传",
            "system_battery_label": "电池",
            "system_battery_health": "电池健康度",
            "system_battery_cycles": "循环计数",
            "system_battery_energy_title": "显著耗能",
            "system_battery_energy_idle": "无显著耗能",
            "settings_system_monitor_card_title": "系统资源监控",
            "settings_system_monitor_card_desc": "在状态栏或面板中实时查看 CPU 与内存占用情况。"
        ],
        "zh-Hant": [
            "system_status_title": "系統狀態",
            "system_cpu_label": "CPU",
            "system_mem_label": "記憶體",
            "system_net_label": "網路",
            "system_net_history": "即時速率走勢 (最近 30 秒)",
            "system_net_download": "下載",
            "system_net_upload": "上傳",
            "system_battery_label": "電池",
            "system_battery_health": "電池健康度",
            "system_battery_cycles": "循環次數",
            "system_battery_energy_title": "高耗能",
            "system_battery_energy_idle": "沒有高耗能項目",
            "settings_system_monitor_card_title": "系統資源監控",
            "settings_system_monitor_card_desc": "在狀態列或面板中即時檢視 CPU 與記憶體使用情況。"
        ],
        "en": [
            "system_status_title": "System Status",
            "system_cpu_label": "CPU",
            "system_mem_label": "Memory",
            "system_net_label": "Network",
            "system_net_history": "Live Network (Last 30s)",
            "system_net_download": "Down",
            "system_net_upload": "Up",
            "system_battery_label": "Battery",
            "system_battery_health": "Battery Health",
            "system_battery_cycles": "Cycle Count",
            "system_battery_energy_title": "Apps Using Significant Energy",
            "system_battery_energy_idle": "No significant energy use",
            "settings_system_monitor_card_title": "System Resource Monitor",
            "settings_system_monitor_card_desc": "View real-time CPU and memory usage in the status bar or panel."
        ],
        "ja": [
            "system_status_title": "システムステータス",
            "system_cpu_label": "CPU",
            "system_mem_label": "メモリ",
            "system_net_label": "ネットワーク",
            "system_net_history": "リアルタイム推移 (直近30秒)",
            "system_net_download": "下り",
            "system_net_upload": "上り",
            "system_battery_label": "バッテリー",
            "system_battery_health": "バッテリー状態",
            "system_battery_cycles": "充放電回数",
            "system_battery_energy_title": "大きなエネルギー使用",
            "system_battery_energy_idle": "大きなエネルギー使用なし",
            "settings_system_monitor_card_title": "システムリソースモニター",
            "settings_system_monitor_card_desc": "ステータスバーまたはパネルでCPUとメモリの使用状況をリアルタイムで確認します。"
        ]
    ]

    /// 规范化语言代码
    private static func normalizeLanguageCode(_ code: String) -> String {
        let cleaned = code.replacingOccurrences(of: "_", with: "-").lowercased()
        if cleaned.starts(with: "zh-hant") || cleaned.starts(with: "zh-tw") || cleaned.starts(with: "zh-hk") {
            return "zh-Hant"
        }
        if cleaned.starts(with: "zh") {
            return "zh-Hans"
        }
        if cleaned.starts(with: "en") {
            return "en"
        }
        if cleaned.starts(with: "ja") {
            return "ja"
        }
        return code
    }

    /// 获取当前应该使用的有效语言代码
    private static func resolveLanguage(_ language: AppState.AppLanguage) -> String {
        if language != .system {
            return language.rawValue
        }

        // 如果是系统默认，我们手动匹配用户最偏好的语言
        let preferred = Bundle.main.preferredLocalizations
        if preferred.contains(where: { $0.lowercased().starts(with: "zh-hant") || $0.lowercased().starts(with: "zh-tw") || $0.lowercased().starts(with: "zh-hk") }) {
            return "zh-Hant"
        }
        if preferred.contains(where: { $0.lowercased().starts(with: "zh") }) {
            return "zh-Hans"
        }
        if preferred.contains(where: { $0.lowercased().starts(with: "ja") }) {
            return "ja"
        }
        return "en"
    }

    /// 通过语言代码获取本地化字符串
    public static func localized(_ key: String, languageCode: String) -> String {
        let normalized = normalizeLanguageCode(languageCode)

        // 1. 优先从内存字典中匹配
        if let dict = systemMonitorDictionary[normalized], let value = dict[key] {
            return value
        }

        // 2. 尝试从 Bundle 加载 .lproj 文件夹
        let currentBundle = bundle
        if let path = currentBundle.path(forResource: languageCode, ofType: "lproj") ??
                      currentBundle.path(forResource: normalized, ofType: "lproj"),
           let langBundle = Bundle(path: path) {
            let val = NSLocalizedString(key, bundle: langBundle, comment: "")
            if val != key {
                return val
            }
        }

        // 大小写兼容兜底 (针对 zh-Hans / zh-hans)
        let altLang = languageCode.lowercased() == "zh-hans" ? "zh-Hans" : languageCode
        if let path = currentBundle.path(forResource: altLang, ofType: "lproj"),
           let langBundle = Bundle(path: path) {
            let val = NSLocalizedString(key, bundle: langBundle, comment: "")
            if val != key {
                return val
            }
        }

        // 3. 兜底当前 Bundle
        let fallback = NSLocalizedString(key, bundle: currentBundle, comment: "")
        if fallback != key {
            return fallback
        }

        // 4. 回退英文内置字典
        if normalized != "en", let enDict = systemMonitorDictionary["en"], let value = enDict[key] {
            return value
        }

        return key
    }

    /// 便捷方法：通过语言字符串获取本地化字符串
    public static func localized(_ key: String, language: String) -> String {
        return localized(key, languageCode: language)
    }

    /// 获取本地化字符串
    public static func localized(_ key: String, language: AppState.AppLanguage = .system) -> String {
        let targetLang = resolveLanguage(language)
        return localized(key, languageCode: targetLang)
    }

    public static func localizedFormat(_ key: String, language: AppState.AppLanguage = .system, _ arguments: CVarArg...) -> String {
        let format = localized(key, language: language)
        return String(format: format, arguments: arguments)
    }

    public static func localizedFormat(_ key: String, language: String, _ arguments: CVarArg...) -> String {
        let format = localized(key, language: language)
        return String(format: format, arguments: arguments)
    }
}
