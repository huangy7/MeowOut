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
        
        // Start Battery Protection
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
        // Stop Battery Protection
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
                // default threshold is 0 if not set, meaning disabled unless user sets it
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
        content.title = "MeowOut 提示"
        content.body = "电池电量已低至保护线，防休眠已自动关闭。"
        
        let request = UNNotificationRequest(identifier: "MeowOutBatteryProtection", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
