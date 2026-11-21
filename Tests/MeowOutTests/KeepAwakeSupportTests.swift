import XCTest
@testable import MeowOut

final class KeepAwakeSupportTests: XCTestCase {
    func testPresetMinutesMatchDesignOrder() {
        XCTAssertEqual(KeepAwakeSupport.presetMinutes, [15, 30, 60, 120, 240, 480, 0])
    }

    func testSanitizedDurationKeepsAllowedValuesAndFallsBackToIndefinite() {
        for valid in [0, 15, 30, 60, 120, 240, 480] {
            XCTAssertEqual(KeepAwakeSupport.sanitizedDuration(valid), valid)
        }
        XCTAssertEqual(KeepAwakeSupport.sanitizedDuration(-10), 0)
        XCTAssertEqual(KeepAwakeSupport.sanitizedDuration(45), 0)
        XCTAssertEqual(KeepAwakeSupport.sanitizedDuration(999), 0)
    }

    func testResolvedUntilDateStaysTodayWhenTimeIsInFuture() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!

        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: 14, minute: 30, second: 0))!
        let picked = cal.date(from: DateComponents(year: 2001, month: 1, day: 15, hour: 18, minute: 15, second: 0))!

        let resolved = KeepAwakeSupport.resolvedUntilDate(picked: picked, now: now, calendar: cal)
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: resolved)

        XCTAssertEqual(comps.year, 2026)
        XCTAssertEqual(comps.month, 11)
        XCTAssertEqual(comps.day, 21)
        XCTAssertEqual(comps.hour, 18)
        XCTAssertEqual(comps.minute, 15)
    }

    func testResolvedUntilDateRollsToTomorrowWhenTimePassedOrEqual() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!

        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: 22, minute: 30, second: 0))!
        let passed = cal.date(from: DateComponents(year: 2001, month: 1, day: 15, hour: 21, minute: 0, second: 0))!
        let sameMinute = cal.date(from: DateComponents(year: 2001, month: 1, day: 15, hour: 22, minute: 30, second: 0))!

        let resolvedPassed = KeepAwakeSupport.resolvedUntilDate(picked: passed, now: now, calendar: cal)
        let passedComps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: resolvedPassed)
        XCTAssertEqual(passedComps.day, 22)
        XCTAssertEqual(passedComps.hour, 21)
        XCTAssertEqual(passedComps.minute, 0)

        let resolvedSame = KeepAwakeSupport.resolvedUntilDate(picked: sameMinute, now: now, calendar: cal)
        let sameComps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: resolvedSame)
        XCTAssertEqual(sameComps.day, 22)
        XCTAssertEqual(sameComps.hour, 22)
        XCTAssertEqual(sameComps.minute, 30)
    }

    func testCountdownTextFormatting() {
        XCTAssertEqual(KeepAwakeSupport.countdownText(remaining: -5), "0:00")
        XCTAssertEqual(KeepAwakeSupport.countdownText(remaining: 0), "0:00")
        XCTAssertEqual(KeepAwakeSupport.countdownText(remaining: 65), "1:05")
        XCTAssertEqual(KeepAwakeSupport.countdownText(remaining: 3599), "59:59")
        XCTAssertEqual(KeepAwakeSupport.countdownText(remaining: 3600), "1:00:00")
        XCTAssertEqual(KeepAwakeSupport.countdownText(remaining: 3912), "1:05:12")
    }

    func testRemainingStatusTextFormatting() {
        XCTAssertEqual(KeepAwakeSupport.remainingStatusText(remaining: 3912), "1h 05m")
        XCTAssertEqual(KeepAwakeSupport.remainingStatusText(remaining: 1805), "30m 05s")
        XCTAssertEqual(KeepAwakeSupport.remainingStatusText(remaining: 42), "42s")
        XCTAssertEqual(KeepAwakeSupport.remainingStatusText(remaining: -3), "0s")
    }

    func testLidSleepIsAllowedEvaluation() {
        // System says lid does not cause sleep -> false
        XCTAssertFalse(KeepAwakeSupport.lidSleepIsAllowed(
            systemAllowsSleep: false,
            externalDisplayConnected: false,
            connectedToPower: false,
            assertions: []
        ))

        // Clamshell desktop mode (AC power + external display) -> false
        XCTAssertFalse(KeepAwakeSupport.lidSleepIsAllowed(
            systemAllowsSleep: true,
            externalDisplayConnected: true,
            connectedToPower: true,
            assertions: []
        ))

        // On battery without lid assertions -> true
        XCTAssertTrue(KeepAwakeSupport.lidSleepIsAllowed(
            systemAllowsSleep: true,
            externalDisplayConnected: false,
            connectedToPower: false,
            assertions: []
        ))

        // Active AppliesOnLidClose PreventSystemSleep assertion blocks lid sleep -> false
        let blockingAssertion: [String: Any] = [
            "AssertType": "PreventSystemSleep",
            "AppliesOnLidClose": true,
            "AssertLevel": 255
        ]
        XCTAssertFalse(KeepAwakeSupport.lidSleepIsAllowed(
            systemAllowsSleep: true,
            externalDisplayConnected: false,
            connectedToPower: false,
            assertions: [blockingAssertion]
        ))

        // Released assertion (AssertLevel == 0) or ordinary idle sleep assertion does not block -> true
        let releasedAssertion: [String: Any] = [
            "AssertType": "PreventSystemSleep",
            "AppliesOnLidClose": true,
            "AssertLevel": 0
        ]
        let idleAssertion: [String: Any] = [
            "AssertType": "PreventUserIdleSystemSleep",
            "AppliesOnLidClose": true,
            "AssertLevel": 255
        ]
        XCTAssertTrue(KeepAwakeSupport.lidSleepIsAllowed(
            systemAllowsSleep: true,
            externalDisplayConnected: false,
            connectedToPower: false,
            assertions: [releasedAssertion, idleAssertion]
        ))
    }
}
