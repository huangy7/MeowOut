import Foundation
import IOKit

public struct BatteryReading: Equatable, Sendable {
    public var hasBattery: Bool
    public var isCharging: Bool
    public var externalConnected: Bool
    public var isCharged: Bool
    public var chargePercent: Int?
    public var watts: Double?
    public var healthPercent: Double?
    public var cycleCount: Int?

    public init(
        hasBattery: Bool = false,
        isCharging: Bool = false,
        externalConnected: Bool = false,
        isCharged: Bool = false,
        chargePercent: Int? = nil,
        watts: Double? = nil,
        healthPercent: Double? = nil,
        cycleCount: Int? = nil
    ) {
        self.hasBattery = hasBattery
        self.isCharging = isCharging
        self.externalConnected = externalConnected
        self.isCharged = isCharged
        self.chargePercent = chargePercent
        self.watts = watts
        self.healthPercent = healthPercent
        self.cycleCount = cycleCount
    }
}

public final class BatterySampler: @unchecked Sendable {
    public static let hasInternalBattery: Bool = {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return false }
        IOObjectRelease(service)
        return true
    }()

    private let hasBatteryOverride: Bool?
    private let propertyReader: @Sendable () -> [String: Any]?
    private let healthPercentReader: @Sendable () -> Double?

    public init(
        hasBatteryOverride: Bool? = nil,
        propertyReader: @escaping @Sendable () -> [String: Any]? = BatterySampler.readBatteryProperties,
        healthPercentReader: (@Sendable () -> Double?)? = nil
    ) {
        self.hasBatteryOverride = hasBatteryOverride
        self.propertyReader = propertyReader
        self.healthPercentReader = healthPercentReader ?? BatterySampler.readExactHealthPercent
    }

    public func sample() -> BatteryReading {
        let hasBattery = hasBatteryOverride ?? Self.hasInternalBattery
        guard hasBattery, let props = propertyReader() else {
            return BatteryReading(hasBattery: false)
        }

        let isCharging = (props["IsCharging"] as? Bool) ?? false
        let externalConnected = (props["ExternalConnected"] as? Bool) ?? false
        let isCharged = (props["FullyCharged"] as? Bool) ?? false

        var chargePercent: Int?
        if let current = Self.intValue(props["CurrentCapacity"]),
           let maxCap = Self.intValue(props["MaxCapacity"]), maxCap > 0 {
            chargePercent = min(100, max(0, Int((Double(current) / Double(maxCap) * 100.0).rounded())))
        }

        var watts: Double?
        let voltageMv = Self.intValue(props["Voltage"]) ?? 0
        let amperageMa = Self.intValue(props["Amperage"])
            ?? Self.intValue(props["InstantAmperage"])
            ?? 0
        if voltageMv > 0, amperageMa != 0 {
            let powerWatts = abs((Double(voltageMv) / 1000.0) * (Double(amperageMa) / 1000.0))
            if powerWatts.isFinite && powerWatts < 500.0 {
                watts = (powerWatts * 10.0).rounded() / 10.0
            }
        }

        var healthPercent: Double?
        if let design = Self.batteryInt("DesignCapacity", in: props), design > 0 {
            let fullCharge = Self.batteryInt("NominalChargeCapacity", in: props)
                ?? Self.batteryInt("FullChargeCapacity", in: props)
                ?? Self.batteryInt("AppleRawMaxCapacity", in: props)
            if let full = fullCharge, full > 0 {
                let health = (Double(full) / Double(design)) * 100.0
                if health.isFinite {
                    healthPercent = min(100.0, max(0.0, (health * 10.0).rounded() / 10.0))
                }
            }
        }

        let cycleCount = Self.batteryInt("CycleCount", in: props)

        // system_profiler exposes Apple's smoothed “Maximum Capacity” value,
        // which is what System Settings shows. The IORegistry ratio above is
        // retained as an immediate fallback while this cached probe runs.
        if let exactHealth = healthPercentReader() {
            healthPercent = Double(exactHealth)
        }

        return BatteryReading(
            hasBattery: true,
            isCharging: isCharging,
            externalConnected: externalConnected,
            isCharged: isCharged,
            chargePercent: chargePercent,
            watts: watts,
            healthPercent: healthPercent,
            cycleCount: cycleCount
        )
    }

    @Sendable public static func readBatteryProperties() -> [String: Any]? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == kIOReturnSuccess,
              let dict = properties?.takeRetainedValue() as? [String: Any]
        else {
            return nil
        }
        return dict
    }

    @Sendable private static func readExactHealthPercent() -> Double? {
        BatteryHealthProbe.shared.refreshIfStale()
        return BatteryHealthProbe.shared.percent.map(Double.init)
    }

    private static func batteryInt(_ key: String, in props: [String: Any]) -> Int? {
        if let value = intValue(props[key]) {
            return value
        }
        if let batteryData = props["BatteryData"] as? [String: Any] {
            return intValue(batteryData[key])
        }
        return nil
    }

    private static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let value as Int:
            return value
        case let value as NSNumber:
            let int64 = value.int64Value
            guard int64 >= Int64(Int.min), int64 <= Int64(Int.max) else { return nil }
            return Int(int64)
        case let value as String:
            return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }
}
