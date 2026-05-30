import Foundation

public enum BuiltInToolType: String, Codable, Equatable {
    case keepAwake
    case keyboardCleaning
    case screenCleaning
    case memosQuickCapture
    case memosOpenBrowser
    case breathing
    
    public var icon: String {
        switch self {
        case .keepAwake: return "☕️"
        case .keyboardCleaning: return "⌨️"
        case .screenCleaning: return "✨"
        case .memosQuickCapture: return "📝"
        case .memosOpenBrowser: return "📖"
        case .breathing: return "🌬"
        }
    }
    
    public func localizedName(language: AppState.AppLanguage) -> String {
        switch self {
        case .keepAwake: return I18n.localized("menu_keep_awake", language: language)
        case .keyboardCleaning: return I18n.localized("menu_keyboard_cleaning", language: language)
        case .screenCleaning: return I18n.localized("menu_screen_cleaning", language: language)
        case .memosQuickCapture: return I18n.localized("memos_settings_quick_capture_short", language: language)
        case .memosOpenBrowser: return I18n.localized("memos_action_open_memos", language: language)
        case .breathing: return I18n.localized("menu_breathing", language: language)
        }
    }
}

public enum QuickTool: Codable, Identifiable, Equatable {
    case builtIn(BuiltInToolType)
    case appShortcut(id: UUID, name: String, path: String, bookmarkData: Data?)

    public var id: String {
        switch self {
        case .builtIn(let type): return type.rawValue
        case .appShortcut(let id, _, _, _): return id.uuidString
        }
    }
    
    public func displayName(language: AppState.AppLanguage) -> String {
        switch self {
        case .builtIn(let type):
            return type.localizedName(language: language)
        case .appShortcut(_, let name, _, _):
            return name
        }
    }
    
    public static func == (lhs: QuickTool, rhs: QuickTool) -> Bool {
        lhs.id == rhs.id
    }
}
