import XCTest
@testable import MeowOut

final class SudoersSupportTests: XCTestCase {
    func testSleepDisabledParsing() {
        let disabledOutput = """
        System-wide power settings:
        Currently in use:
         standby              1
         SleepDisabled        1
         displaysleep         10
        """
        XCTAssertTrue(SudoersSupport.sleepDisabled(inPmsetOutput: disabledOutput))

        let enabledOutput = """
        System-wide power settings:
        Currently in use:
         standby              1
         SleepDisabled        0
         displaysleep         10
        """
        XCTAssertFalse(SudoersSupport.sleepDisabled(inPmsetOutput: enabledOutput))
        XCTAssertFalse(SudoersSupport.sleepDisabled(inPmsetOutput: ""))
    }

    func testClamshellRuleUsesNumericUid() {
        XCTAssertEqual(
            SudoersSupport.clamshellRule(uid: 501),
            "#501 ALL=(root) NOPASSWD: /usr/bin/pmset disablesleep 1, /usr/bin/pmset disablesleep 0"
        )
    }
}
