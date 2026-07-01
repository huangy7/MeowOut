import Foundation
import IOKit.ps

@MainActor
class BatteryMonitor: ObservableObject {
    static let shared = BatteryMonitor()
    
    @Published var isOnBattery: Bool = false
    @Published var batteryPercentage: Int = 100
    
    private var timer: Timer?
    
    private init() {
        updateBatteryInfo()
    }
    
    func startMonitoring() {
        stopMonitoring()
        timer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateBatteryInfo()
            }
        }
        updateBatteryInfo()
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
    
    private func updateBatteryInfo() {
        let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as Array
        
        var foundBattery = false
        
        for ps in sources {
            let info = IOPSGetPowerSourceDescription(snapshot, ps).takeUnretainedValue() as! [String: Any]
            
            if let type = info[kIOPSTypeKey] as? String, type == kIOPSInternalBatteryType {
                foundBattery = true
                
                if let powerSourceState = info[kIOPSPowerSourceStateKey] as? String {
                    self.isOnBattery = (powerSourceState == kIOPSBatteryPowerValue)
                }
                
                if let capacity = info[kIOPSCurrentCapacityKey] as? Int,
                   let maxCapacity = info[kIOPSMaxCapacityKey] as? Int, maxCapacity > 0 {
                    self.batteryPercentage = Int((Double(capacity) / Double(maxCapacity)) * 100.0)
                }
                break
            }
        }
        
        if !foundBattery {
            self.isOnBattery = false
            self.batteryPercentage = 100
        }
    }
}
