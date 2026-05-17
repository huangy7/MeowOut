// Sources/MeowOut/AppState.swift
import Foundation
import Observation
import SwiftUI

public enum AppPhase: Equatable {
    case working
    case idle
    case alerting
    case resting
    case paused
}

public enum PetPersonality: String, CaseIterable, Identifiable {
    case gentle, strict, tsundere
    public var id: String { rawValue }
}

@Observable
public final class AppState {
    private enum Keys: String {
        case workDurationMinutes
        case alertBeforeRestMinutes
        case restDurationMinutes
        case enableCursorChasing
        case restToResetMinutes
        case language
    }

    public enum AppLanguage: String, CaseIterable, Identifiable {
        case system, en, zhHans = "zh-hans"
        public var id: String { rawValue }
        public func displayName(currentLanguage: AppLanguage) -> String {
            switch self {
            case .system: return I18n.localized("settings_language_system", language: currentLanguage)
            case .en: return "English"
            case .zhHans: return "简体中文"
            }
        }
    }

    public var language: AppLanguage {
        get {
            access(keyPath: \.language)
            return AppLanguage(rawValue: UserDefaults.standard.string(forKey: Keys.language.rawValue) ?? "system") ?? .system
        }
        set {
            withMutation(keyPath: \.language) {
                UserDefaults.standard.set(newValue.rawValue, forKey: Keys.language.rawValue)
            }
        }
    }

    // Persistent Settings
    public var workDurationMinutes: Int {
        get {
            access(keyPath: \.workDurationMinutes)
            let value = UserDefaults.standard.integer(forKey: Keys.workDurationMinutes.rawValue)
            return value != 0 ? value : 45
        }
        set {
            withMutation(keyPath: \.workDurationMinutes) {
                UserDefaults.standard.set(newValue, forKey: Keys.workDurationMinutes.rawValue)
            }
        }
    }

    public var alertBeforeRestMinutes: Int {
        get {
            access(keyPath: \.alertBeforeRestMinutes)
            let value = UserDefaults.standard.integer(forKey: Keys.alertBeforeRestMinutes.rawValue)
            return value != 0 ? value : 5
        }
        set {
            withMutation(keyPath: \.alertBeforeRestMinutes) {
                UserDefaults.standard.set(newValue, forKey: Keys.alertBeforeRestMinutes.rawValue)
            }
        }
    }

    public var restDurationMinutes: Int {
        get {
            access(keyPath: \.restDurationMinutes)
            let value = UserDefaults.standard.integer(forKey: Keys.restDurationMinutes.rawValue)
            return value != 0 ? value : 5
        }
        set {
            withMutation(keyPath: \.restDurationMinutes) {
                UserDefaults.standard.set(newValue, forKey: Keys.restDurationMinutes.rawValue)
            }
        }
    }

    public var enableCursorChasing: Bool {
        get {
            access(keyPath: \.enableCursorChasing)
            return UserDefaults.standard.object(forKey: Keys.enableCursorChasing.rawValue) as? Bool ?? true
        }
        set {
            withMutation(keyPath: \.enableCursorChasing) {
                UserDefaults.standard.set(newValue, forKey: Keys.enableCursorChasing.rawValue)
            }
        }
    }

    public var restToResetMinutes: Int {
        get {
            access(keyPath: \.restToResetMinutes)
            let value = UserDefaults.standard.integer(forKey: Keys.restToResetMinutes.rawValue)
            return value != 0 ? value : 5
        }
        set {
            withMutation(keyPath: \.restToResetMinutes) {
                UserDefaults.standard.set(newValue, forKey: Keys.restToResetMinutes.rawValue)
            }
        }
    }

    // Derived properties for internal logic
    public var maxWorkTime: TimeInterval { TimeInterval(workDurationMinutes * 60) }
    public var alertThreshold: TimeInterval { TimeInterval((workDurationMinutes - alertBeforeRestMinutes) * 60) }
    public var defaultRestTime: TimeInterval { TimeInterval(restDurationMinutes * 60) }
    public var resetThreshold: TimeInterval { TimeInterval(restToResetMinutes * 60) }
    public var rollbackThreshold: TimeInterval {
        let a = Double(restToResetMinutes)
        return min(180, (a / 2.5) * 60) // c = min(3m, a/2.5)
    }

    // Transient State
    public var currentState: AppPhase = .working
    public var workElapsed: TimeInterval = 0
    public var isPaused: Bool = false
    public var restRemaining: TimeInterval = 0
    public var pauseRemaining: TimeInterval = 0
    public var isWalking: Bool = true
    public var currentFrameIndex: Int = 0

    // Statistics
    private var _workHistoryCache: [String: TimeInterval]?

    public var workHistory: [String: TimeInterval] {
        get { 
            access(keyPath: \.workHistory)
            if let cache = _workHistoryCache { return cache }
            let saved = UserDefaults.standard.dictionary(forKey: "workHistory") as? [String: TimeInterval] ?? [:] 
            _workHistoryCache = saved
            return saved
        }
        set { 
            withMutation(keyPath: \.workHistory) {
                _workHistoryCache = newValue
                // Note: We don't save to UserDefaults here to avoid high-frequency IO
            }
        }
    }

    /// 强制将内存中的统计数据持久化到磁盘
    public func flushStatsToDisk() {
        if let cache = _workHistoryCache {
            UserDefaults.standard.set(cache, forKey: "workHistory")
            print("📊 Stats persisted to disk.")
        }
    }

    public var totalWorkToday: TimeInterval {
        let key = dateKey(for: Date())
        return workHistory[key] ?? 0
    }

    public var lastStatResetDate: Date? {
        get { UserDefaults.standard.object(forKey: "lastStatResetDate") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "lastStatResetDate") }
    }

    public var dailyWorkGoal: Int {
        get { access(keyPath: \.dailyWorkGoal); let val = UserDefaults.standard.integer(forKey: "dailyWorkGoal"); return val != 0 ? val : 8 }
        set { withMutation(keyPath: \.dailyWorkGoal) { UserDefaults.standard.set(newValue, forKey: "dailyWorkGoal") } }
    }

    public var selectedPersonality: PetPersonality {
        get { access(keyPath: \.selectedPersonality); return PetPersonality(rawValue: UserDefaults.standard.string(forKey: "selectedPersonality") ?? "") ?? .strict }
        set { withMutation(keyPath: \.selectedPersonality) { UserDefaults.standard.set(newValue.rawValue, forKey: "selectedPersonality") } }
    }

    public func dateKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }


    public init() {}

    public func resetToDefaults() {
        withMutation(keyPath: \.workDurationMinutes) {
            UserDefaults.standard.removeObject(forKey: Keys.workDurationMinutes.rawValue)
        }
        withMutation(keyPath: \.alertBeforeRestMinutes) {
            UserDefaults.standard.removeObject(forKey: Keys.alertBeforeRestMinutes.rawValue)
        }
        withMutation(keyPath: \.restDurationMinutes) {
            UserDefaults.standard.removeObject(forKey: Keys.restDurationMinutes.rawValue)
        }
        withMutation(keyPath: \.enableCursorChasing) {
            UserDefaults.standard.removeObject(forKey: Keys.enableCursorChasing.rawValue)
        }
        withMutation(keyPath: \.restToResetMinutes) {
            UserDefaults.standard.removeObject(forKey: Keys.restToResetMinutes.rawValue)
        }

        // Reset statistics too
        withMutation(keyPath: \.workHistory) {
            UserDefaults.standard.removeObject(forKey: "workHistory")
        }
        lastStatResetDate = Date()

        // SMAppService (Launch at Login) is separate and should be toggled manually by user,
        // but we could unregister here if desired. Let's keep it for safety.
    }
}
