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

    /// 获取当前应该使用的有效语言代码
    private static func resolveLanguage(_ language: AppState.AppLanguage) -> String {
        if language != .system {
            return language.rawValue
        }

        // 如果是系统默认，我们手动匹配用户最偏好的语言
        let preferred = Bundle.main.preferredLocalizations
        // 优先匹配 zh-hans 或 en
        if preferred.contains("zh-hans") { return "zh-hans" }
        if preferred.contains("zh-Hans") { return "zh-hans" }
        return "en"
    }

    /// 获取本地化字符串
    public static func localized(_ key: String, language: AppState.AppLanguage = .system) -> String {
        let currentBundle = bundle
        let targetLang = resolveLanguage(language)

        // 尝试加载对应语言的 .lproj 文件夹
        if let path = currentBundle.path(forResource: targetLang, ofType: "lproj"),
           let langBundle = Bundle(path: path) {
            return NSLocalizedString(key, bundle: langBundle, comment: "")
        }

        // 大小写兼容兜底 (针对 zh-Hans / zh-hans)
        let altLang = targetLang == "zh-hans" ? "zh-Hans" : targetLang
        if let path = currentBundle.path(forResource: altLang, ofType: "lproj"),
           let langBundle = Bundle(path: path) {
            return NSLocalizedString(key, bundle: langBundle, comment: "")
        }

        // 最终兜底
        return NSLocalizedString(key, bundle: currentBundle, comment: "")
    }

    public static func localizedFormat(_ key: String, language: AppState.AppLanguage = .system, _ arguments: CVarArg...) -> String {
        let format = localized(key, language: language)
        return String(format: format, arguments: arguments)
    }
}
