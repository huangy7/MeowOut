import Combine
import XCTest
@testable import MeowOut

final class SystemMonitorI18nTests: XCTestCase {
    func testSystemMonitorI18nKeysExistAndNotEmpty() {
        let languages = ["zh-Hans", "zh-Hant", "en", "ja"]
        let keys = [
            "system_status_title",
            "system_cpu_label",
            "system_mem_label",
            "system_net_label",
            "system_net_history",
            "system_net_download",
            "system_net_upload",
            "system_battery_label",
            "system_battery_health",
            "system_battery_cycles",
            "system_battery_energy_title",
            "system_battery_energy_idle",
            "settings_system_monitor_card_title",
            "settings_system_monitor_card_desc"
        ]

        for lang in languages {
            for key in keys {
                let localized = I18n.localized(key, language: lang)
                XCTAssertFalse(localized.isEmpty, "Key '\(key)' should not be empty for language '\(lang)'")
                XCTAssertNotEqual(localized, key, "Key '\(key)' should be localized for language '\(lang)' and not equal to the key itself")
            }
        }
    }

    func testTrayCardsCustomizationI18nKeysExist() {
        let keys = [
            "rest_reminder_enabled",
            "rest_reminder_enabled_desc",
            "quick_tools_enabled",
            "quick_tools_enabled_desc"
        ]
        let languages = ["zh-Hans", "zh-Hant", "en", "ja"]
        for lang in languages {
            for key in keys {
                let localized = I18n.localized(key, language: lang)
                XCTAssertFalse(localized.isEmpty, "Key '\(key)' should not be empty for '\(lang)'")
                XCTAssertNotEqual(localized, key, "Key '\(key)' should be localized for '\(lang)'")
            }
        }
    }

    func testHealthConsolidationI18nKeysExist() {
        let keys = [
            "settings_tab_health",
            "settings_subtab_work_rest",
            "settings_subtab_water",
            "settings_subtab_daily_goals"
        ]
        let languages = ["zh-Hans", "zh-Hant", "en", "ja"]
        for lang in languages {
            for key in keys {
                let localized = I18n.localized(key, language: lang)
                XCTAssertFalse(localized.isEmpty, "Key '\(key)' should not be empty for '\(lang)'")
                XCTAssertNotEqual(localized, key, "Key '\(key)' should be localized for '\(lang)'")
            }
        }
    }
}

final class SystemMetricsServiceTests: XCTestCase {
    func testFormatUptime() {
        // Chinese formats
        XCTAssertEqual(SystemMetricsService.formatUptime(seconds: 90000, language: "zh-Hans"), "已开机 1天1时")
        XCTAssertEqual(SystemMetricsService.formatUptime(seconds: 90000, language: "zh-Hant"), "已开机 1天1时")
        XCTAssertEqual(SystemMetricsService.formatUptime(seconds: 3700, language: "zh-Hans"), "已开机 1时1分")
        XCTAssertEqual(SystemMetricsService.formatUptime(seconds: 90, language: "zh-Hans"), "已开机 1分")
        XCTAssertEqual(SystemMetricsService.formatUptime(seconds: 0, language: "zh-Hans"), "已开机 0分")
        XCTAssertEqual(SystemMetricsService.formatUptime(seconds: -10, language: "zh"), "已开机 0分")

        // English / Other formats
        XCTAssertEqual(SystemMetricsService.formatUptime(seconds: 90000, language: "en"), "Up 1d 1h")
        XCTAssertEqual(SystemMetricsService.formatUptime(seconds: 3700, language: "en"), "Up 1h 1m")
        XCTAssertEqual(SystemMetricsService.formatUptime(seconds: 90, language: "en"), "Up 1m")
        XCTAssertEqual(SystemMetricsService.formatUptime(seconds: 0, language: "en"), "Up 0m")
        XCTAssertEqual(SystemMetricsService.formatUptime(seconds: 3700, language: "ja"), "Up 1h 1m")
    }

    func testFormatMemoryBytes() {
        let gb: UInt64 = 1024 * 1024 * 1024
        let mb: UInt64 = 1024 * 1024
        let kb: UInt64 = 1024

        XCTAssertEqual(SystemMetricsService.formatBytes(gb), "1.0 GB")
        XCTAssertEqual(SystemMetricsService.formatBytes(UInt64(1.5 * Double(gb))), "1.5 GB")
        XCTAssertEqual(SystemMetricsService.formatBytes(500 * mb), "500 MB")
        XCTAssertEqual(SystemMetricsService.formatBytes(500 * kb), "500 KB")
        XCTAssertEqual(SystemMetricsService.formatBytes(0), "0 KB")
    }

    func testCPUTickDeltaCalculation() {
        // Normal 20% usage
        let prev = SystemMetricsService.CPUTicks(busy: 100, total: 1000)
        let curr = SystemMetricsService.CPUTicks(busy: 300, total: 2000)
        let usage = SystemMetricsService.calculateUsage(previous: prev, current: curr)
        XCTAssertEqual(usage, 0.2, accuracy: 0.0001)

        // 100% usage
        let fullCurr = SystemMetricsService.CPUTicks(busy: 1100, total: 2000)
        let fullUsage = SystemMetricsService.calculateUsage(previous: prev, current: fullCurr)
        XCTAssertEqual(fullUsage, 1.0, accuracy: 0.0001)

        // Zero delta in total ticks
        let zeroTotal = SystemMetricsService.calculateUsage(previous: prev, current: prev)
        XCTAssertEqual(zeroTotal, 0.0)

        // Negative total delta (reset or error)
        let resetTotal = SystemMetricsService.calculateUsage(previous: curr, current: prev)
        XCTAssertEqual(resetTotal, 0.0)

        // Decreasing busy ticks
        let decBusy = SystemMetricsService.CPUTicks(busy: 50, total: 2000)
        let decUsage = SystemMetricsService.calculateUsage(previous: prev, current: decBusy)
        XCTAssertEqual(decUsage, 0.0)
    }

    func testRealMetricsReadDoesNotCrash() {
        let service = SystemMetricsService()
        let snapshot = service.readSnapshot()

        XCTAssertGreaterThanOrEqual(snapshot.cpuUsage, 0.0)
        XCTAssertLessThanOrEqual(snapshot.cpuUsage, 1.0)

        XCTAssertGreaterThan(snapshot.memoryTotal, 0)
        XCTAssertGreaterThan(snapshot.memoryUsed, 0)
        XCTAssertLessThanOrEqual(snapshot.memoryUsed, snapshot.memoryTotal)

        XCTAssertGreaterThanOrEqual(snapshot.memoryUsagePercentage, 0.0)
        XCTAssertLessThanOrEqual(snapshot.memoryUsagePercentage, 1.0)

        XCTAssertGreaterThan(snapshot.uptimeSeconds, 0)

        // Check snapshot init default values
        let emptySnapshot = SystemMetricsSnapshot()
        XCTAssertEqual(emptySnapshot.cpuUsage, 0.0)
        XCTAssertEqual(emptySnapshot.memoryUsed, 0)
        XCTAssertEqual(emptySnapshot.memoryTotal, 0)
        XCTAssertEqual(emptySnapshot.uptimeSeconds, 0)
        XCTAssertEqual(emptySnapshot.memoryUsagePercentage, 0.0)
        XCTAssertEqual(emptySnapshot.battery, BatteryReading())

        // Verify process sampling runs without crash
        let cpuProcesses = service.sampleTopProcesses(kind: .cpu)
        XCTAssertLessThanOrEqual(cpuProcesses.count, 5)

        let memProcesses = service.sampleTopProcesses(kind: .memory)
        XCTAssertLessThanOrEqual(memProcesses.count, 5)
    }

    func testBreakdownKindIncludesNetwork() {
        let allCases = BreakdownKind.allCases
        XCTAssertTrue(allCases.contains(.network))
    }

    func testFormatSpeed() {
        XCTAssertEqual(SystemMetricsService.formatSpeed(0), "0 KB/s")
        XCTAssertEqual(SystemMetricsService.formatSpeed(500), "0 KB/s") // < 1024
        XCTAssertEqual(SystemMetricsService.formatSpeed(1500), "1.5 KB/s")
        XCTAssertEqual(SystemMetricsService.formatSpeed(1024 * 1024 * 2.5), "2.5 MB/s")
        XCTAssertEqual(SystemMetricsService.formatSpeed(1024 * 1024 * 1024 * 1.2), "1.2 GB/s")
    }

    func testNetworkHistoryBufferLimit() {
        var snapshot = SystemMetricsSnapshot()
        for i in 1...35 {
            snapshot.appendNetworkHistory(down: Double(i), up: Double(i * 2))
        }
        XCTAssertEqual(snapshot.netDownHistory.count, 30)
        XCTAssertEqual(snapshot.netUpHistory.count, 30)
        XCTAssertEqual(snapshot.netDownHistory.first, 6.0)
        XCTAssertEqual(snapshot.netDownHistory.last, 35.0)
    }

    func testFormatSpeedEdgeCasesAndRounding() {
        // Negative, NaN, Infinity
        XCTAssertEqual(SystemMetricsService.formatSpeed(-1), "0 KB/s")
        XCTAssertEqual(SystemMetricsService.formatSpeed(-1000), "0 KB/s")
        XCTAssertEqual(SystemMetricsService.formatSpeed(Double.nan), "0 KB/s")
        XCTAssertEqual(SystemMetricsService.formatSpeed(Double.infinity), "0 KB/s")
        XCTAssertEqual(SystemMetricsService.formatSpeed(-Double.infinity), "0 KB/s")

        // Rounding boundary: KB -> MB
        XCTAssertEqual(SystemMetricsService.formatSpeed(1024 * 1023.94), "1023.9 KB/s")
        XCTAssertEqual(SystemMetricsService.formatSpeed(1024 * 1023.96), "1.0 MB/s")

        // Rounding boundary: MB -> GB
        XCTAssertEqual(SystemMetricsService.formatSpeed(1024 * 1024 * 1023.94), "1023.9 MB/s")
        XCTAssertEqual(SystemMetricsService.formatSpeed(1024 * 1024 * 1023.96), "1.0 GB/s")
    }

    func testNetworkHistoryBufferLimitWithInvalidMaxCount() {
        var snapshot = SystemMetricsSnapshot()
        snapshot.appendNetworkHistory(down: 10, up: 20, maxCount: 30)
        XCTAssertEqual(snapshot.netDownHistory.count, 1)
        XCTAssertEqual(snapshot.netUpHistory.count, 1)

        // maxCount == 0 clears buffer without crash
        snapshot.appendNetworkHistory(down: 30, up: 40, maxCount: 0)
        XCTAssertEqual(snapshot.netDownHistory.count, 0)
        XCTAssertEqual(snapshot.netUpHistory.count, 0)

        // negative maxCount clears buffer without crash
        snapshot.appendNetworkHistory(down: 50, up: 60, maxCount: -5)
        XCTAssertEqual(snapshot.netDownHistory.count, 0)
        XCTAssertEqual(snapshot.netUpHistory.count, 0)
    }

    func testConsecutiveReadSnapshotAccumulatesHistory() {
        let service = SystemMetricsService()
        let snap1 = service.readSnapshot()
        XCTAssertEqual(snap1.netDownHistory.count, 1)
        XCTAssertEqual(snap1.netUpHistory.count, 1)

        let snap2 = service.readSnapshot()
        XCTAssertEqual(snap2.netDownHistory.count, 2)
        XCTAssertEqual(snap2.netUpHistory.count, 2)

        let snap3 = service.readSnapshot()
        XCTAssertEqual(snap3.netDownHistory.count, 3)
        XCTAssertEqual(snap3.netUpHistory.count, 3)
    }

    func testBreakdownKindIncludesBattery() {
        let allCases = BreakdownKind.allCases
        XCTAssertTrue(allCases.contains(.battery))
    }

    func testFormatBatteryWatts() {
        XCTAssertEqual(SystemMetricsService.formatBatteryWatts(18.2), "18.2W")
        XCTAssertEqual(SystemMetricsService.formatBatteryWatts(0.0), "0W")
        XCTAssertEqual(SystemMetricsService.formatBatteryWatts(nil), "--")
        XCTAssertEqual(SystemMetricsService.formatBatteryWatts(-5.0), "--")
        XCTAssertEqual(SystemMetricsService.formatBatteryWatts(.nan), "--")
        XCTAssertEqual(SystemMetricsService.formatBatteryWatts(.infinity), "--")
    }

    func testSampleTopProcessesBattery() {
        let service = SystemMetricsService()
        // 首次采样自适应建立观测窗口并计算首批即时差值，避免首屏空态
        let initialItems = service.sampleTopProcesses(kind: .battery)
        XCTAssertLessThanOrEqual(initialItems.count, 5)
        for item in initialItems {
            XCTAssertFalse(item.name.isEmpty, "Process name should not be empty")
            XCTAssertGreaterThanOrEqual(item.cpuPercent, 0.0, "Energy score should be non-negative")
        }

        // 二次增量采样应持续保持有效
        let deltaItems = service.sampleTopProcesses(kind: .battery)
        XCTAssertLessThanOrEqual(deltaItems.count, 5)
        for item in deltaItems {
            XCTAssertFalse(item.name.isEmpty, "Process name should not be empty")
            XCTAssertGreaterThanOrEqual(item.cpuPercent, 0.0, "Energy score should be non-negative")
        }
    }

    func testRefreshTopProcessesBatteryPopulatesTopEnergyProcesses() {
        let service = SystemMetricsService()
        let expectation = expectation(description: "topEnergyProcesses populated")

        var cancellable: AnyCancellable?
        cancellable = service.$topEnergyProcesses
            .dropFirst()
            .sink { items in
                XCTAssertLessThanOrEqual(items.count, 5)
                for item in items {
                    XCTAssertFalse(item.name.isEmpty, "Process name should not be empty")
                    XCTAssertGreaterThanOrEqual(item.cpuPercent, 0.0, "Energy score should be non-negative")
                }
                expectation.fulfill()
            }

        service.refreshTopProcesses(kind: .battery)

        wait(for: [expectation], timeout: 5.0)
        _ = cancellable
    }

    func testSampleTopProcessesEnergyIsolation() {
        let service = SystemMetricsService()
        let energyItems1 = service.sampleTopProcesses(kind: .battery)
        XCTAssertLessThanOrEqual(energyItems1.count, 5)

        let cpuItems1 = service.sampleTopProcesses(kind: .cpu)
        XCTAssertLessThanOrEqual(cpuItems1.count, 5)

        Thread.sleep(forTimeInterval: 0.15)

        let energyItems2 = service.sampleTopProcesses(kind: .battery)
        XCTAssertLessThanOrEqual(energyItems2.count, 5)

        let cpuItems2 = service.sampleTopProcesses(kind: .cpu)
        XCTAssertLessThanOrEqual(cpuItems2.count, 5)
    }
}
