import Foundation
import IOKit.pwr_mgt
import Combine
import UserNotifications

@MainActor
final class PowerAssertionService: ObservableObject {
    static let shared = PowerAssertionService()

    private var idleSleepAssertionID: IOPMAssertionID = 0
    private var displaySleepAssertionID: IOPMAssertionID = 0
    private var batteryCancellable: AnyCancellable?

    @Published var isKeepingAwake: Bool = false

    private init() {}

    func enable() throws {
        guard !isKeepingAwake else { return }

        let reason = "MeowOut Keep Awake" as CFString
        var idleAssertion: IOPMAssertionID = 0
        let idleResult = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoIdleSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &idleAssertion
        )

        guard idleResult == kIOReturnSuccess else {
            throw NSError(domain: "PowerAssertionService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to enable Keep Awake."])
        }

        var displayAssertion: IOPMAssertionID = 0
        let displayResult = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &displayAssertion
        )

        guard displayResult == kIOReturnSuccess else {
            IOPMAssertionRelease(idleAssertion)
            throw NSError(domain: "PowerAssertionService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to keep the display awake."])
        }

        idleSleepAssertionID = idleAssertion
        displaySleepAssertionID = displayAssertion
        isKeepingAwake = true
        
        // 若用户配置了合盖后继续运行偏好，联动激活底层合盖模式
        if ClamshellManager.shared.isClamshellPreferred {
            _ = ClamshellManager.shared.enableClamshell()
        }
        
        // 启动电池保护监控
        startBatteryProtection()
    }

    func disable() {
        guard isKeepingAwake else { return }

        if idleSleepAssertionID != 0 {
            IOPMAssertionRelease(idleSleepAssertionID)
            idleSleepAssertionID = 0
        }

        if displaySleepAssertionID != 0 {
            IOPMAssertionRelease(displaySleepAssertionID)
            displaySleepAssertionID = 0
        }
        
        isKeepingAwake = false
        
        // 联动还原合盖不休眠设置，并在闭盖时安全触发系统睡眠
        if ClamshellManager.shared.isClamshellActive {
            _ = ClamshellManager.shared.disableClamshell()
        }
        
        // 停止电池保护监控
        stopBatteryProtection()
    }
    
    // MARK: - Battery Protection
    
    private func startBatteryProtection() {
        BatteryMonitor.shared.startMonitoring()
        
        batteryCancellable = BatteryMonitor.shared.$batteryPercentage
            .combineLatest(BatteryMonitor.shared.$isOnBattery)
            .sink { [weak self] percentage, isOnBattery in
                guard let self = self, self.isKeepingAwake else { return }
                
                let threshold = UserDefaults.standard.integer(forKey: "batteryProtectionThreshold")
                // 默认 0 为关闭，大于 0 时在处于电池供电且电量低于阈值时触发保护
                guard threshold > 0 else { return }
                
                if isOnBattery && percentage <= threshold {
                    self.triggerBatteryProtection()
                }
            }
    }
    
    private func stopBatteryProtection() {
        batteryCancellable?.cancel()
        batteryCancellable = nil
        BatteryMonitor.shared.stopMonitoring()
    }
    
    private func triggerBatteryProtection() {
        disable()
        sendBatteryNotification()
    }
    
    private func sendBatteryNotification() {
        let content = UNMutableNotificationContent()
        content.title = I18n.localized("power_battery_notification_title", language: AppState().language)
        content.body = I18n.localized("power_battery_notification_body", language: AppState().language)
        
        let request = UNNotificationRequest(identifier: "MeowOutBatteryProtection", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
