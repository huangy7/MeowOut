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
    case breathing
    case overworking
}

public enum PetPersonality: String, CaseIterable, Identifiable {
    case gentle, strict, tsundere
    public var id: String { rawValue }
}

public enum SettingsNavigationTarget: Equatable {
    case update
}

public struct SessionLog: Identifiable, Equatable {
    public let id = UUID()
    public let startTime: Date
    public var endTime: Date?
    public let phase: AppPhase
    
    public init(startTime: Date = Date(), endTime: Date? = nil, phase: AppPhase) {
        self.startTime = startTime
        self.endTime = endTime
        self.phase = phase
    }
}

@Observable
public final class AppState {
    public enum PetType: String, CaseIterable, Identifiable {
        case clawd = "Clawd"
        case robot = "Robot"
        case cloud = "Cloud"
        case horse = "Horse"
        public var id: String { rawValue }
    }

    private enum Keys: String {
        case workDurationMinutes
        case alertBeforeRestMinutes
        case restDurationMinutes
        case enableCursorChasing
        case restToResetMinutes
        case language
        case selectedPet
        case enableGlobalKeyboardScold
        case waterReminderEnabled
        case waterReminderMode
        case waterCustomInterval
        case dailyWaterGoal
        case todayWaterCups
        case lastWaterResetDate
        case lastNotifiedUpdateVersion
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

    public enum WaterReminderMode: String, CaseIterable, Identifiable {
        case followRhythm = "followRhythm"
        case custom = "custom"
        public var id: String { rawValue }
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

    public var selectedPet: PetType {
        get {
            access(keyPath: \.selectedPet)
            return PetType(rawValue: UserDefaults.standard.string(forKey: Keys.selectedPet.rawValue) ?? "Clawd") ?? .clawd
        }
        set {
            withMutation(keyPath: \.selectedPet) {
                UserDefaults.standard.set(newValue.rawValue, forKey: Keys.selectedPet.rawValue)
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

    public var enableGlobalKeyboardScold: Bool {
        get {
            access(keyPath: \.enableGlobalKeyboardScold)
            return UserDefaults.standard.object(forKey: Keys.enableGlobalKeyboardScold.rawValue) as? Bool ?? false
        }
        set {
            withMutation(keyPath: \.enableGlobalKeyboardScold) {
                UserDefaults.standard.set(newValue, forKey: Keys.enableGlobalKeyboardScold.rawValue)
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

    public var lastNotifiedUpdateVersion: String? {
        get {
            access(keyPath: \.lastNotifiedUpdateVersion)
            return UserDefaults.standard.string(forKey: Keys.lastNotifiedUpdateVersion.rawValue)
        }
        set {
            withMutation(keyPath: \.lastNotifiedUpdateVersion) {
                UserDefaults.standard.set(newValue, forKey: Keys.lastNotifiedUpdateVersion.rawValue)
            }
        }
    }

    public func resetUpdateReminderMemory() {
        lastNotifiedUpdateVersion = nil
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
    public var dailyLogs: [SessionLog] = []

    private var _currentState: AppPhase = .working
    public var currentState: AppPhase {
        get { _currentState }
        set { changeState(to: newValue) }
    }

    public func changeState(to newPhase: AppPhase, at date: Date = Date()) {
        guard _currentState != newPhase else { return }
        let oldPhase = _currentState
        _currentState = newPhase
        
        // Smart merge for Resting <-> Overworking <-> Breathing
        if let last = dailyLogs.last {
            let duration = date.timeIntervalSince(last.startTime)
            if duration < 60 {
                let isMergeable = (oldPhase == .resting && newPhase == .overworking) ||
                                  (oldPhase == .overworking && newPhase == .resting) ||
                                  (oldPhase == .resting && newPhase == .breathing) ||
                                  (oldPhase == .overworking && newPhase == .breathing) ||
                                  (oldPhase == .working && (newPhase == .resting || newPhase == .overworking))
                
                if isMergeable {
                    dailyLogs.removeLast()
                    dailyLogs.append(SessionLog(startTime: last.startTime, phase: newPhase))
                    return
                }
            }
        }
        
        if !dailyLogs.isEmpty {
            dailyLogs[dailyLogs.count - 1].endTime = date
        }
        dailyLogs.append(SessionLog(startTime: date, phase: newPhase))
    }

    public func recordPhaseTransition(from oldPhase: AppPhase, to newPhase: AppPhase, at date: Date = Date()) {
        changeState(to: newPhase, at: date)
    }

    public var workElapsed: TimeInterval = 0 {
        didSet {
            if workElapsed == 0 {
                warningDismissed = false
            }
        }
    }
    public var warningDismissed: Bool = false
    public var isPaused: Bool = false
    public var restRemaining: TimeInterval = 0
    public var pauseRemaining: TimeInterval = 0
    public var isWalking: Bool = true
    public var currentFrameIndex: Int = 0
    public var isPreviewing: Bool = false
    public var isBreathingActive: Bool = false
    public var settingsNavigationTarget: SettingsNavigationTarget?

    // Water Reminder
    public var waterReminderEnabled: Bool {
        get {
            access(keyPath: \.waterReminderEnabled)
            return UserDefaults.standard.object(forKey: Keys.waterReminderEnabled.rawValue) as? Bool ?? true
        }
        set {
            withMutation(keyPath: \.waterReminderEnabled) {
                UserDefaults.standard.set(newValue, forKey: Keys.waterReminderEnabled.rawValue)
            }
        }
    }

    public var waterReminderMode: WaterReminderMode {
        get {
            access(keyPath: \.waterReminderMode)
            return WaterReminderMode(rawValue: UserDefaults.standard.string(forKey: Keys.waterReminderMode.rawValue) ?? "followRhythm") ?? .followRhythm
        }
        set {
            withMutation(keyPath: \.waterReminderMode) {
                UserDefaults.standard.set(newValue.rawValue, forKey: Keys.waterReminderMode.rawValue)
            }
        }
    }

    public var waterCustomInterval: Int {
        get {
            access(keyPath: \.waterCustomInterval)
            let val = UserDefaults.standard.integer(forKey: Keys.waterCustomInterval.rawValue)
            return val != 0 ? val : 45
        }
        set {
            withMutation(keyPath: \.waterCustomInterval) {
                UserDefaults.standard.set(newValue, forKey: Keys.waterCustomInterval.rawValue)
            }
        }
    }

    public var dailyWaterGoal: Int {
        get {
            access(keyPath: \.dailyWaterGoal)
            let val = UserDefaults.standard.integer(forKey: Keys.dailyWaterGoal.rawValue)
            return val != 0 ? val : 8
        }
        set {
            withMutation(keyPath: \.dailyWaterGoal) {
                UserDefaults.standard.set(newValue, forKey: Keys.dailyWaterGoal.rawValue)
            }
        }
    }

    public var todayWaterCups: Int {
        get {
            access(keyPath: \.todayWaterCups)
            return UserDefaults.standard.integer(forKey: Keys.todayWaterCups.rawValue)
        }
        set {
            withMutation(keyPath: \.todayWaterCups) {
                UserDefaults.standard.set(newValue, forKey: Keys.todayWaterCups.rawValue)
            }
        }
    }

    public var lastWaterResetDate: Date? {
        get { UserDefaults.standard.object(forKey: Keys.lastWaterResetDate.rawValue) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: Keys.lastWaterResetDate.rawValue) }
    }

    public var lastWaterReminderTime: Date?

    public func cleanupShortBreathingLog() {
        guard let last = dailyLogs.last, last.phase == .breathing else { return }
        let duration = Date().timeIntervalSince(last.startTime)
        if duration < 30 {
            dailyLogs.removeLast()
            if !dailyLogs.isEmpty {
                dailyLogs[dailyLogs.count - 1].endTime = nil
            }
        }
    }

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

    public func checkAndResetWaterIfNewDay() {
        let now = Date()
        let calendar = Calendar.current
        if let lastReset = lastWaterResetDate {
            if !calendar.isDate(now, inSameDayAs: lastReset) {
                todayWaterCups = 0
                lastWaterResetDate = now
            }
        } else {
            lastWaterResetDate = now
        }
    }

    public init() {
        dailyLogs.append(SessionLog(phase: currentState))
    }

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
        withMutation(keyPath: \.enableGlobalKeyboardScold) {
            UserDefaults.standard.removeObject(forKey: Keys.enableGlobalKeyboardScold.rawValue)
        }

        // Reset statistics too
        withMutation(keyPath: \.workHistory) {
            UserDefaults.standard.removeObject(forKey: "workHistory")
        }
        lastStatResetDate = Date()

        // SMAppService (Launch at Login) is separate and should be toggled manually by user,
        // but we could unregister here if desired. Let's keep it for safety.
    }

    public func resetIntervalsToDefaults() {
        withMutation(keyPath: \.workDurationMinutes) {
            UserDefaults.standard.removeObject(forKey: Keys.workDurationMinutes.rawValue)
        }
        withMutation(keyPath: \.alertBeforeRestMinutes) {
            UserDefaults.standard.removeObject(forKey: Keys.alertBeforeRestMinutes.rawValue)
        }
        withMutation(keyPath: \.restDurationMinutes) {
            UserDefaults.standard.removeObject(forKey: Keys.restDurationMinutes.rawValue)
        }
        withMutation(keyPath: \.restToResetMinutes) {
            UserDefaults.standard.removeObject(forKey: Keys.restToResetMinutes.rawValue)
        }
        withMutation(keyPath: \.dailyWorkGoal) {
            UserDefaults.standard.removeObject(forKey: "dailyWorkGoal")
        }
    }
}

public protocol PetSpriteView: View {
    init(pose: ClawdPose, height: CGFloat, isWalking: Bool)
}

extension AppState.PetType {
    @ViewBuilder
    public func makeView(pose: ClawdPose, height: CGFloat, isWalking: Bool) -> some View {
        switch self {
        case .clawd: ClawdView(pose: pose, height: height, isWalking: isWalking)
        case .robot: TerminalView(pose: pose, height: height, isWalking: isWalking)
        case .cloud: CloudView(pose: pose, height: height, isWalking: isWalking)
        case .horse: HorseView(pose: pose, height: height, isWalking: isWalking)
        }
    }
}
