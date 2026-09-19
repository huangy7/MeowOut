import XCTest
@testable import MeowOut

final class BatterySamplerTests: XCTestCase {
    func testMockBatteryPropertiesParsing() {
        let mockProps: [String: Any] = [
            "CurrentCapacity": 4200,
            "MaxCapacity": 5000,
            "IsCharging": true,
            "ExternalConnected": true,
            "FullyCharged": false,
            "Voltage": 12000, // 12V
            "Amperage": 1500, // 1.5A -> 18W
            "CycleCount": 86,
            "DesignCapacity": 5200,
            "NominalChargeCapacity": 5000 // 5000/5200 = 96.15%
        ]

        let sampler = BatterySampler(
            hasBatteryOverride: true,
            propertyReader: { mockProps },
            healthPercentReader: { nil }
        )
        let reading = sampler.sample()

        XCTAssertTrue(reading.hasBattery)
        XCTAssertTrue(reading.isCharging)
        XCTAssertTrue(reading.externalConnected)
        XCTAssertFalse(reading.isCharged)
        XCTAssertEqual(reading.chargePercent, 84) // 4200 / 5000 * 100
        XCTAssertEqual(reading.watts ?? 0, 18.0, accuracy: 0.01)
        XCTAssertEqual(reading.cycleCount, 86)
        XCTAssertEqual(reading.healthPercent ?? 0, 96.2, accuracy: 0.1)
    }

    func testMockDischargingBattery() {
        let mockProps: [String: Any] = [
            "CurrentCapacity": 3000,
            "MaxCapacity": 6000,
            "IsCharging": false,
            "ExternalConnected": false,
            "FullyCharged": false,
            "Voltage": 11500,
            "InstantAmperage": -1200, // -13.8W
            "CycleCount": 120,
            "DesignCapacity": 6000,
            "NominalChargeCapacity": 5800
        ]

        let sampler = BatterySampler(hasBatteryOverride: true, propertyReader: { mockProps })
        let reading = sampler.sample()

        XCTAssertTrue(reading.hasBattery)
        XCTAssertFalse(reading.isCharging)
        XCTAssertFalse(reading.externalConnected)
        XCTAssertEqual(reading.chargePercent, 50)
        XCTAssertEqual(reading.watts ?? 0, 13.8, accuracy: 0.01)
    }

    func testDesktopWithoutBattery() {
        let sampler = BatterySampler(hasBatteryOverride: false, propertyReader: { nil })
        let reading = sampler.sample()

        XCTAssertFalse(reading.hasBattery)
        XCTAssertNil(reading.chargePercent)
        XCTAssertNil(reading.watts)
        XCTAssertNil(reading.healthPercent)
    }

    func testNestedAndNSNumberBatteryValuesAreParsed() {
        let mockProps: [String: Any] = [
            "CurrentCapacity": NSNumber(value: 4500),
            "MaxCapacity": NSNumber(value: 5000),
            "IsCharging": false,
            "ExternalConnected": false,
            "Voltage": NSNumber(value: 12000),
            "InstantAmperage": NSNumber(value: -1000),
            "BatteryData": [
                "DesignCapacity": NSNumber(value: 6000),
                "NominalChargeCapacity": NSNumber(value: 5700),
                "CycleCount": NSNumber(value: 44)
            ]
        ]

        let sampler = BatterySampler(
            hasBatteryOverride: true,
            propertyReader: { mockProps },
            healthPercentReader: { nil }
        )
        let reading = sampler.sample()

        XCTAssertEqual(reading.chargePercent, 90)
        XCTAssertEqual(reading.watts ?? 0, 12.0, accuracy: 0.01)
        XCTAssertEqual(reading.healthPercent ?? 0, 95.0, accuracy: 0.1)
        XCTAssertEqual(reading.cycleCount, 44)
    }

    func testLiveSystemSamplerSmokeTest() {
        let sampler = BatterySampler()
        let reading = sampler.sample()
        if reading.hasBattery {
            if let charge = reading.chargePercent {
                XCTAssertTrue((0...100).contains(charge))
            }
        }
    }
}
