import Combine
import Foundation
import IOKit
import IOKit.ps
import IOKit.pwr_mgt
import UserNotifications

@MainActor
final class PowerAssertionService: ObservableObject {
    static let shared = PowerAssertionService()

    enum EndReason {
        case manual
        case timer
        case battery
        case quit
    }

    private enum DefaultsKey {
        static let defaultDuration = "keepAwakeDefaultDuration"
        static let switchUsesUntil = "keepAwakeSwitchUsesUntil"
        static let untilTime = "keepAwakeUntilTime"
        static let clamshellPreferred = "enableClamshellMode"
        static let didModifySleepDisabled = "didModifySleepDisabled"
        static let dimScreenOnLidClose = "dimScreenOnLidClose"
        static let dimmedDisplaySavedBrightness = "dimmedDisplaySavedBrightness"
        static let batteryProtectionThreshold = "batteryProtectionThreshold"
    }

    // MARK: - Published State

    @Published private(set) var isKeepingAwake: Bool = false
    @Published private(set) var endDate: Date? = nil
    /// 预设档位对应的分钟数（0 表示永久）；通过「直到…」启动时为 nil。
    @Published private(set) var sessionMinutes: Int? = nil

    @Published private(set) var lastPickedMinutes: Int
    @Published private(set) var switchUsesUntil: Bool
    @Published private(set) var savedUntilTime: Double

    @Published private(set) var clamshellActive: Bool = false {
        didSet {
            guard clamshellActive != oldValue else { return }
            syncLidDimmingObserver()
        }
    }
    @Published private(set) var passwordlessClamshell: Bool = false
    @Published private(set) var clamshellSetupInProgress: Bool = false
    @Published private(set) var clamshellSetupFailed: Bool = false

    /// 持久化会话偏好：开启后仅在防休眠生效期间禁止合盖休眠，会话结束自动恢复。
    @Published var clamshellPreferred: Bool {
        didSet {
            guard clamshellPreferred != oldValue else { return }
            UserDefaults.standard.set(clamshellPreferred, forKey: DefaultsKey.clamshellPreferred)
            clamshellSetupFailed = false
            guard !isTerminating else { return }
            if clamshellPreferred {
                applyClamshellPreference()
            } else if clamshellNeedsRestore {
                clamshellSetupInProgress = false
                clamshellSetupID = nil
                disableClamshell(synchronous: false)
            } else {
                clamshellSetupInProgress = false
                clamshellSetupID = nil
            }
        }
    }

    /// 持久化偏好：合盖不休眠生效期间自动将内置屏亮度降至 0，开盖后自动恢复原亮度。
    @Published var dimScreenOnLidClose: Bool {
        didSet {
            guard dimScreenOnLidClose != oldValue else { return }
            UserDefaults.standard.set(dimScreenOnLidClose, forKey: DefaultsKey.dimScreenOnLidClose)
            if !dimScreenOnLidClose {
                applyDimmingAction(LidDimmingSupport.restoring(saved: savedDisplayBrightness))
            }
            syncLidDimmingObserver()
        }
    }

    // MARK: - Private State

    private var idleSleepAssertionID: IOPMAssertionID = 0
    private var displaySleepAssertionID: IOPMAssertionID = 0
    private var endTimer: Timer?
    private var batteryCancellable: AnyCancellable?

    private var isTerminating = false
    private var clamshellEnablePending = false
    private var clamshellRestorePending = false
    private var clamshellOperationGeneration = 0
    private var clamshellSetupID: UUID?
    private var clamshellSetupRetried = false

    private var lidSleepGeneration = 0
    private var lidSleepAttemptsRemaining = 0

    private var lidDimmingNotificationPort: IONotificationPortRef?
    private var lidDimmingNotification: io_object_t = 0
    private var lidClosedForDimming: Bool?
    private var savedDisplayBrightness: Double?

    private init() {
        let defaults = UserDefaults.standard
        self.lastPickedMinutes = KeepAwakeSupport.sanitizedDuration(
            defaults.integer(forKey: DefaultsKey.defaultDuration)
        )
        self.switchUsesUntil = defaults.bool(forKey: DefaultsKey.switchUsesUntil)
        self.savedUntilTime = defaults.double(forKey: DefaultsKey.untilTime)
        self.clamshellPreferred = defaults.bool(forKey: DefaultsKey.clamshellPreferred)
        self.dimScreenOnLidClose = defaults.bool(forKey: DefaultsKey.dimScreenOnLidClose)
        refreshPasswordlessStatus()
    }

    // MARK: - Public Session API

    func toggle() {
        if isKeepingAwake {
            deactivate(reason: .manual)
        } else {
            startLastPick()
        }
    }

    /// 按上次使用的档位一键启动；若上次是「直到某时刻」且尚未过期则复用，否则回退到上次预设时长。
    func startLastPick() {
        if switchUsesUntil {
            let savedEnd = Date(timeIntervalSinceReferenceDate: savedUntilTime)
            if savedEnd > Date() {
                activate(until: savedEnd)
                return
            }
        }
        activate(minutes: lastPickedMinutes)
    }

    /// 以预设分钟数启动（0 表示永久）。
    func activate(minutes: Int) {
        let sanitized = KeepAwakeSupport.sanitizedDuration(minutes)
        let end = sanitized > 0 ? Date().addingTimeInterval(TimeInterval(sanitized) * 60) : nil
        startSession(end: end, minutes: sanitized)
        guard isKeepingAwake else { return }

        lastPickedMinutes = sanitized
        switchUsesUntil = false
        UserDefaults.standard.set(sanitized, forKey: DefaultsKey.defaultDuration)
        UserDefaults.standard.set(false, forKey: DefaultsKey.switchUsesUntil)
    }

    /// 启动定时防休眠直到指定未来时刻。
    func activate(until date: Date) {
        guard date > Date() else { return }
        startSession(end: date, minutes: nil)
        guard isKeepingAwake else { return }

        switchUsesUntil = true
        savedUntilTime = date.timeIntervalSinceReferenceDate
        UserDefaults.standard.set(true, forKey: DefaultsKey.switchUsesUntil)
        UserDefaults.standard.set(savedUntilTime, forKey: DefaultsKey.untilTime)
    }

    /// 快捷延长当前定时会话。
    func extend(minutes: Int) {
        guard isKeepingAwake, let current = endDate, minutes > 0 else { return }
        let newEnd = max(current, Date()).addingTimeInterval(TimeInterval(minutes) * 60)
        endDate = newEnd
        scheduleEnd(at: newEnd)
        if sessionMinutes == nil {
            savedUntilTime = newEnd.timeIntervalSinceReferenceDate
            UserDefaults.standard.set(savedUntilTime, forKey: DefaultsKey.untilTime)
        }
    }

    func deactivate(reason: EndReason) {
        let hadSession = isKeepingAwake
        if reason == .quit {
            isTerminating = true
            clamshellSetupID = nil
            clamshellSetupInProgress = false
        }

        endTimer?.invalidate()
        endTimer = nil
        endDate = nil
        sessionMinutes = nil

        releaseAssertions()
        isKeepingAwake = false
        stopBatteryProtection()

        if clamshellNeedsRestore {
            disableClamshell(synchronous: reason == .quit)
        } else if reason == .quit, lidSleepAttemptsRemaining > 0 {
            sleepIfLidAlreadyClosed(attemptsLeft: lidSleepAttemptsRemaining, synchronous: true)
        }

        if hadSession, reason == .battery {
            sendBatteryNotification()
        }
    }

    /// 兼容旧调用的简单关闭入口。
    func disable() {
        deactivate(reason: .manual)
    }

    // MARK: - Formatting Helpers

    /// 未开启时防休眠磁贴的副标题（显示上次记住的档位）。
    func lastPickSubtitle(language: AppState.AppLanguage, now: Date = Date()) -> String {
        if switchUsesUntil {
            let savedEnd = Date(timeIntervalSinceReferenceDate: savedUntilTime)
            if savedEnd > now {
                let timeStr = Self.shortTimeFormatter.string(from: savedEnd)
                return I18n.localizedFormat("keep_awake_until_value_format", language: language, timeStr)
            }
        }
        let label = KeepAwakeSupport.shortChipTitle(for: lastPickedMinutes, language: language)
        return I18n.localizedFormat("keep_awake_default_pick_format", language: language, label)
    }

    /// 开启时防休眠磁贴的副标题。
    func activeTileSubtitle(language: AppState.AppLanguage, now: Date = Date()) -> String {
        guard isKeepingAwake else {
            return lastPickSubtitle(language: language, now: now)
        }
        if let end = endDate {
            if sessionMinutes == nil {
                let timeStr = Self.shortTimeFormatter.string(from: end)
                return I18n.localizedFormat("keep_awake_until_value_format", language: language, timeStr)
            }
            let countdown = KeepAwakeSupport.countdownText(remaining: end.timeIntervalSince(now))
            return I18n.localizedFormat("keep_awake_remaining_compact_format", language: language, countdown)
        }
        return I18n.localized("keep_awake_active_indefinite", language: language)
    }

    func clamshellStatusCaption(language: AppState.AppLanguage) -> String {
        if clamshellSetupInProgress {
            return I18n.localized("power_clamshell_status_configuring", language: language)
        }
        if clamshellSetupFailed {
            return I18n.localized("power_clamshell_status_failed", language: language)
        }
        if clamshellActive {
            return I18n.localized("power_clamshell_status_active", language: language)
        }
        if clamshellPreferred {
            return I18n.localized("power_clamshell_status_ready_waiting", language: language)
        }
        return passwordlessClamshell
            ? I18n.localized("power_clamshell_status_ready", language: language)
            : I18n.localized("power_clamshell_status_needs_auth", language: language)
    }

    private static let shortTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    // MARK: - Internal Session Activation

    private func startSession(end: Date?, minutes: Int?) {
        guard !isTerminating else { return }

        // 若已触发低电量保护，拒绝启动防休眠，避免创建孤立 assertion
        if batteryProtectionPercent() != nil {
            return
        }

        lidSleepGeneration &+= 1
        lidSleepAttemptsRemaining = 0
        endTimer?.invalidate()
        endTimer = nil

        guard ensureAssertions() else { return }

        sessionMinutes = minutes
        endDate = end
        isKeepingAwake = true

        if let end {
            scheduleEnd(at: end)
        }

        startBatteryProtection()
        guard isKeepingAwake else { return }

        if clamshellPreferred {
            applyClamshellPreference()
        }
    }

    private func scheduleEnd(at date: Date) {
        endTimer?.invalidate()
        let timer = Timer(fire: date, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.deactivate(reason: .timer)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        endTimer = timer
    }

    // MARK: - IOKit Assertions

    private func ensureAssertions() -> Bool {
        let reason = "MeowOut Keep Awake" as CFString

        if idleSleepAssertionID == 0 {
            var idleAssertion: IOPMAssertionID = 0
            let idleResult = IOPMAssertionCreateWithName(
                kIOPMAssertionTypeNoIdleSleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason,
                &idleAssertion
            )
            guard idleResult == kIOReturnSuccess else {
                return false
            }
            idleSleepAssertionID = idleAssertion
        }

        if displaySleepAssertionID == 0 {
            var displayAssertion: IOPMAssertionID = 0
            let displayResult = IOPMAssertionCreateWithName(
                kIOPMAssertionTypeNoDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason,
                &displayAssertion
            )
            guard displayResult == kIOReturnSuccess else {
                releaseAssertions()
                return false
            }
            displaySleepAssertionID = displayAssertion
        }

        return true
    }

    private func releaseAssertions() {
        if idleSleepAssertionID != 0 {
            IOPMAssertionRelease(idleSleepAssertionID)
            idleSleepAssertionID = 0
        }
        if displaySleepAssertionID != 0 {
            IOPMAssertionRelease(displaySleepAssertionID)
            displaySleepAssertionID = 0
        }
    }

    // MARK: - Battery Protection

    /// 当前是否正处于低电量保护拦截状态；返回当前电量百分比，允许启动时返回 nil。
    func batteryProtectionPercent() -> Int? {
        let threshold = UserDefaults.standard.integer(forKey: DefaultsKey.batteryProtectionThreshold)
        guard threshold > 0 else { return nil }
        guard let snapshot = Self.readLiveBatteryState(),
              snapshot.isOnBattery,
              snapshot.percentage <= threshold else {
            return nil
        }
        return snapshot.percentage
    }

    private static func readLiveBatteryState() -> (isOnBattery: Bool, percentage: Int)? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }
        for ps in sources {
            guard let info = IOPSGetPowerSourceDescription(snapshot, ps)?.takeUnretainedValue() as? [String: Any],
                  let type = info[kIOPSTypeKey] as? String,
                  type == kIOPSInternalBatteryType else {
                continue
            }
            let isOnBattery = (info[kIOPSPowerSourceStateKey] as? String) == kIOPSBatteryPowerValue
            if let capacity = info[kIOPSCurrentCapacityKey] as? Int,
               let maxCapacity = info[kIOPSMaxCapacityKey] as? Int,
               maxCapacity > 0 {
                let pct = Int((Double(capacity) / Double(maxCapacity)) * 100.0)
                return (isOnBattery, pct)
            }
        }
        return nil
    }

    private func startBatteryProtection() {
        BatteryMonitor.shared.startMonitoring()
        batteryCancellable?.cancel()
        batteryCancellable = BatteryMonitor.shared.$batteryPercentage
            .combineLatest(BatteryMonitor.shared.$isOnBattery)
            .sink { [weak self] percentage, isOnBattery in
                guard let self, self.isKeepingAwake else { return }
                let threshold = UserDefaults.standard.integer(forKey: DefaultsKey.batteryProtectionThreshold)
                guard threshold > 0 else { return }
                if isOnBattery && percentage <= threshold {
                    self.deactivate(reason: .battery)
                }
            }
    }

    private func stopBatteryProtection() {
        batteryCancellable?.cancel()
        batteryCancellable = nil
        BatteryMonitor.shared.stopMonitoring()
    }

    private func sendBatteryNotification() {
        let content = UNMutableNotificationContent()
        content.title = "MeowOut"
        content.body = I18n.localized("power_battery_triggered_notification")
        let request = UNNotificationRequest(
            identifier: "MeowOutBatteryProtection",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Closed Lid (pmset disablesleep)

    func refreshPasswordlessStatus() {
        guard !isTerminating, !clamshellRestorePending else { return }
        let generation = clamshellOperationGeneration
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let configured = SudoersManager.isConfigured()
            Task { @MainActor [weak self] in
                guard let self,
                      !self.isTerminating,
                      !self.clamshellRestorePending,
                      self.clamshellOperationGeneration == generation else { return }
                self.passwordlessClamshell = configured
            }
        }
    }

    private var clamshellNeedsRestore: Bool {
        clamshellActive
            || clamshellEnablePending
            || clamshellRestorePending
            || UserDefaults.standard.bool(forKey: DefaultsKey.didModifySleepDisabled)
    }

    private func applyClamshellPreference() {
        guard !isTerminating, !clamshellRestorePending else { return }
        clamshellSetupRetried = false
        if passwordlessClamshell {
            if isKeepingAwake {
                enableClamshell()
            }
        } else {
            prepareClamshellPreference()
        }
    }

    private func prepareClamshellPreference() {
        guard !isTerminating,
              !clamshellRestorePending,
              clamshellPreferred,
              !clamshellSetupInProgress else { return }

        let requestID = UUID()
        clamshellSetupID = requestID
        clamshellSetupInProgress = true
        clamshellSetupFailed = false

        let installPrompt = I18n.localized("power_clamshell_admin_install_prompt")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let configured = SudoersManager.isConfigured()
            Task { @MainActor [weak self] in
                guard let self, !self.isTerminating, self.clamshellSetupID == requestID else { return }
                if configured {
                    self.finishClamshellSetup(ok: true, requestID: requestID)
                } else {
                    SudoersManager.install(prompt: installPrompt) { [weak self] ok in
                        Task { @MainActor [weak self] in
                            self?.finishClamshellSetup(ok: ok, requestID: requestID)
                        }
                    }
                }
            }
        }
    }

    private func finishClamshellSetup(ok: Bool, requestID: UUID) {
        guard !isTerminating, clamshellSetupID == requestID else { return }
        clamshellSetupID = nil
        clamshellSetupInProgress = false
        passwordlessClamshell = ok

        guard ok else {
            markClamshellSetupFailed()
            return
        }

        if isKeepingAwake, clamshellPreferred {
            enableClamshell()
        }
    }

    private func markClamshellSetupFailed() {
        clamshellSetupInProgress = false
        guard clamshellPreferred else { return }
        clamshellPreferred = false
        clamshellSetupFailed = true
    }

    private func enableClamshell() {
        guard !isTerminating,
              isKeepingAwake,
              clamshellPreferred,
              !clamshellActive,
              !clamshellEnablePending,
              !clamshellRestorePending else { return }

        clamshellOperationGeneration &+= 1
        let generation = clamshellOperationGeneration
        clamshellEnablePending = true

        // 提交命令前先落盘恢复标记，防止崩溃后遗留系统级 disablesleep 1
        UserDefaults.standard.set(true, forKey: DefaultsKey.didModifySleepDisabled)

        SudoersManager.pmsetDisableSleep(true) { [weak self] ok in
            Task { @MainActor [weak self] in
                guard let self, !self.isTerminating, self.clamshellOperationGeneration == generation else { return }
                self.clamshellEnablePending = false
                guard ok else {
                    self.passwordlessClamshell = false
                    guard self.isKeepingAwake, self.clamshellPreferred else { return }
                    if self.clamshellSetupRetried {
                        self.markClamshellSetupFailed()
                    } else {
                        self.clamshellSetupRetried = true
                        self.prepareClamshellPreference()
                    }
                    return
                }

                self.passwordlessClamshell = true
                if self.isKeepingAwake, self.clamshellPreferred {
                    self.clamshellActive = true
                } else {
                    self.disableClamshell(synchronous: false)
                }
            }
        }
    }

    private func disableClamshell(synchronous: Bool) {
        guard synchronous || !clamshellRestorePending else { return }
        clamshellSetupID = nil
        clamshellSetupInProgress = false
        clamshellOperationGeneration &+= 1
        let generation = clamshellOperationGeneration
        lidSleepGeneration &+= 1
        lidSleepAttemptsRemaining = 0
        clamshellActive = false
        clamshellEnablePending = false
        clamshellRestorePending = true

        if synchronous {
            let ok = SudoersManager.pmsetDisableSleep(false)
            finishClamshellRestore(ok: ok, usedPasswordless: true, generation: generation, synchronous: true)
            return
        }

        let restorePrompt = I18n.localized("power_clamshell_admin_restore_prompt")
        SudoersManager.pmsetDisableSleep(false) { [weak self] ok in
            Task { @MainActor [weak self] in
                guard let self, !self.isTerminating, self.clamshellOperationGeneration == generation else { return }
                if ok {
                    self.finishClamshellRestore(ok: true, usedPasswordless: true, generation: generation, synchronous: false)
                } else {
                    SudoersManager.restoreSleepWithAuthorization(
                        prompt: restorePrompt,
                        shouldProceed: { [weak self] in
                            guard let self else { return false }
                            return MainActor.assumeIsolated {
                                !self.isTerminating && self.clamshellOperationGeneration == generation
                            }
                        }
                    ) { [weak self] restored in
                        Task { @MainActor [weak self] in
                            guard let self, !self.isTerminating else { return }
                            self.finishClamshellRestore(ok: restored, usedPasswordless: false, generation: generation, synchronous: false)
                        }
                    }
                }
            }
        }
    }

    private func finishClamshellRestore(
        ok: Bool,
        usedPasswordless: Bool,
        generation: Int,
        synchronous: Bool
    ) {
        guard clamshellOperationGeneration == generation else { return }
        clamshellRestorePending = false
        if !usedPasswordless {
            passwordlessClamshell = false
        }
        guard ok else { return }
        UserDefaults.standard.set(false, forKey: DefaultsKey.didModifySleepDisabled)

        if !isTerminating, isKeepingAwake, clamshellPreferred {
            enableClamshell()
        } else {
            sleepIfLidAlreadyClosed(synchronous: synchronous)
        }
    }

    /// 清除 disablesleep 仅重置内核标志；若结束时盖子早已合着，macOS 不会重新评估合盖事件，
    /// 必须主动请求 IOPMSleepSystem（带重试以等待 powerd 同步标志）。
    private func sleepIfLidAlreadyClosed(
        attemptsLeft: Int = 10,
        synchronous: Bool = false,
        generation: Int? = nil
    ) {
        let currentGeneration = generation ?? lidSleepGeneration
        guard currentGeneration == lidSleepGeneration else { return }
        lidSleepAttemptsRemaining = 0
        guard !isKeepingAwake, !clamshellActive else { return }
        guard LidDisplayDimmer.lidClosed() == true, Self.lidSleepIsAllowed() else { return }

        let rootDomain = IOPMFindPowerManagement(kIOMainPortDefault)
        guard rootDomain != 0 else { return }
        let result = IOPMSleepSystem(rootDomain)
        IOServiceClose(rootDomain)

        guard result != kIOReturnSuccess, attemptsLeft > 1 else { return }
        if synchronous {
            Thread.sleep(forTimeInterval: 0.5)
            sleepIfLidAlreadyClosed(attemptsLeft: attemptsLeft - 1, synchronous: true, generation: currentGeneration)
        } else {
            lidSleepAttemptsRemaining = attemptsLeft - 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, !self.isTerminating else { return }
                    self.sleepIfLidAlreadyClosed(attemptsLeft: attemptsLeft - 1, generation: currentGeneration)
                }
            }
        }
    }

    private static func lidSleepIsAllowed() -> Bool {
        let allowsSleep = LidDisplayDimmer.systemClamshellCausesSleep()
        guard allowsSleep == true else { return false }

        var snapshot: Unmanaged<CFDictionary>?
        let result = IOPMCopyAssertionsByProcess(&snapshot)
        let values = snapshot?.takeRetainedValue()
        guard result == kIOReturnSuccess,
              let assertions = values as? [AnyHashable: [[String: Any]]] else {
            return false
        }

        let connectedToPower = readLiveBatteryState().map { !$0.isOnBattery }
        return KeepAwakeSupport.lidSleepIsAllowed(
            systemAllowsSleep: allowsSleep,
            externalDisplayConnected: LidDisplayDimmer.hasExternalDisplay(),
            connectedToPower: connectedToPower,
            assertions: assertions.values.flatMap { $0 }
        )
    }

    // MARK: - Startup Crash Recovery

    /// App 启动时调用：恢复上次异常退出遗留的暗屏亮度与系统 `SleepDisabled 1`。
    func recoverIfNeeded() {
        guard !isTerminating else { return }
        recoverDimmedDisplayIfNeeded()

        guard UserDefaults.standard.bool(forKey: DefaultsKey.didModifySleepDisabled) else {
            return
        }

        clamshellSetupID = nil
        clamshellSetupInProgress = false
        clamshellOperationGeneration &+= 1
        let generation = clamshellOperationGeneration
        clamshellRestorePending = true

        let recoverPrompt = I18n.localized("power_clamshell_admin_recover_prompt")

        let finish: @MainActor (Bool) -> Void = { [weak self] ok in
            guard let self, !self.isTerminating, self.clamshellOperationGeneration == generation else { return }
            self.clamshellRestorePending = false
            if ok {
                UserDefaults.standard.set(false, forKey: DefaultsKey.didModifySleepDisabled)
            }
            if ok, self.isKeepingAwake, self.clamshellPreferred {
                self.enableClamshell()
            }
        }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let state = SudoersManager.readSleepDisabledState()
            if state.ok, !state.disabled {
                Task { @MainActor in finish(true) }
            } else if SudoersManager.pmsetDisableSleep(false) {
                Task { @MainActor in finish(true) }
            } else {
                Task { @MainActor [weak self] in
                    guard let self, !self.isTerminating, self.clamshellOperationGeneration == generation else { return }
                    SudoersManager.restoreSleepWithAuthorization(
                        prompt: recoverPrompt,
                        shouldProceed: { [weak self] in
                            guard let self else { return false }
                            return MainActor.assumeIsolated {
                                !self.isTerminating && self.clamshellOperationGeneration == generation
                            }
                        }
                    ) { ok in
                        Task { @MainActor in finish(ok) }
                    }
                }
            }
        }
    }

    // MARK: - Closed-Lid Built-In Display Dimming

    private func recoverDimmedDisplayIfNeeded() {
        guard let saved = UserDefaults.standard.object(forKey: DefaultsKey.dimmedDisplaySavedBrightness) as? Double else {
            return
        }
        savedDisplayBrightness = saved
        applyDimmingAction(.restore(saved))
        syncLidDimmingObserver()
    }

    private func syncLidDimmingObserver() {
        let armed = clamshellActive && dimScreenOnLidClose
        if !armed {
            applyDimmingAction(LidDimmingSupport.restoring(saved: savedDisplayBrightness))
        }

        guard armed || savedDisplayBrightness != nil else {
            if lidDimmingNotification != 0 {
                IOObjectRelease(lidDimmingNotification)
                lidDimmingNotification = 0
            }
            if let port = lidDimmingNotificationPort {
                IONotificationPortDestroy(port)
                lidDimmingNotificationPort = nil
            }
            lidClosedForDimming = nil
            return
        }

        guard lidDimmingNotificationPort == nil else { return }
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return }
        defer { IOObjectRelease(root) }

        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        let result = IOServiceAddInterestNotification(
            port,
            root,
            kIOGeneralInterest,
            { context, _, _, _ in
                guard let context else { return }
                let manager = Unmanaged<PowerAssertionService>.fromOpaque(context).takeUnretainedValue()
                DispatchQueue.main.async { [weak manager] in
                    Task { @MainActor [weak manager] in
                        manager?.lidStateMayHaveChangedForDimming()
                    }
                }
            },
            Unmanaged.passUnretained(self).toOpaque(),
            &lidDimmingNotification
        )

        guard result == KERN_SUCCESS else {
            IONotificationPortDestroy(port)
            return
        }

        lidDimmingNotificationPort = port
        IONotificationPortSetDispatchQueue(port, DispatchQueue.main)
        lidClosedForDimming = LidDisplayDimmer.lidClosed()

        // 启用选项时盖子可能已经合着（例如接外接屏操作），此时不会再触发新的合盖通知
        if armed, lidClosedForDimming == true, savedDisplayBrightness == nil {
            applyDimmingAction(
                LidDimmingSupport.lidClosed(currentBrightness: LidDisplayDimmer.currentBrightness())
            )
        }
    }

    private func lidStateMayHaveChangedForDimming() {
        guard (clamshellActive && dimScreenOnLidClose) || savedDisplayBrightness != nil else { return }
        let closed = LidDisplayDimmer.lidClosed() ?? false
        guard closed != lidClosedForDimming else { return }
        lidClosedForDimming = closed

        if closed {
            if clamshellActive, dimScreenOnLidClose {
                applyDimmingAction(
                    LidDimmingSupport.lidClosed(currentBrightness: LidDisplayDimmer.currentBrightness())
                )
            }
        } else {
            applyDimmingAction(LidDimmingSupport.restoring(saved: savedDisplayBrightness))
        }
    }

    private func applyDimmingAction(_ action: LidDimmingSupport.Action) {
        switch action {
        case .dim(let save):
            savedDisplayBrightness = save
            UserDefaults.standard.set(save, forKey: DefaultsKey.dimmedDisplaySavedBrightness)
            LidDisplayDimmer.setBrightness(0)
        case .restore(let value):
            attemptDisplayRestore(value)
        case .none:
            break
        }
    }

    private func attemptDisplayRestore(_ value: Double, attemptsLeft: Int = 6) {
        guard LidDisplayDimmer.setBrightness(value) else {
            guard attemptsLeft > 1 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                Task { @MainActor [weak self] in
                    self?.attemptDisplayRestore(value, attemptsLeft: attemptsLeft - 1)
                }
            }
            return
        }
        savedDisplayBrightness = nil
        UserDefaults.standard.removeObject(forKey: DefaultsKey.dimmedDisplaySavedBrightness)
        syncLidDimmingObserver()
    }
}
