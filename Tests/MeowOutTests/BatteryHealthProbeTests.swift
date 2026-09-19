import Foundation
import XCTest
@testable import MeowOut

final class BatteryHealthProbeTests: XCTestCase {
    func testParsesNestedStringMaximumCapacity() {
        let data = Data(#"{"SPPowerDataType":[{"_items":[{"sppower_battery_health_maximum_capacity":"95%"}]}]}"#.utf8)
        XCTAssertEqual(BatteryHealthProbe.percent(fromSystemProfilerJSON: data), 95)
    }

    func testParsesNumericMaximumCapacity() {
        let data = Data(#"{"sppower_battery_health_maximum_capacity":88}"#.utf8)
        XCTAssertEqual(BatteryHealthProbe.percent(fromSystemProfilerJSON: data), 88)
    }

    func testRejectsMissingOrInvalidMaximumCapacity() {
        let missing = Data(#"{"SPPowerDataType":[]}"#.utf8)
        let invalid = Data(#"{"sppower_battery_health_maximum_capacity":"-"}"#.utf8)
        let outOfRange = Data(#"{"sppower_battery_health_maximum_capacity":101}"#.utf8)

        XCTAssertNil(BatteryHealthProbe.percent(fromSystemProfilerJSON: missing))
        XCTAssertNil(BatteryHealthProbe.percent(fromSystemProfilerJSON: invalid))
        XCTAssertNil(BatteryHealthProbe.percent(fromSystemProfilerJSON: outOfRange))
    }
}
