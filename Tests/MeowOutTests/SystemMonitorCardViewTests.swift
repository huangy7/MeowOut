import XCTest
@testable import MeowOut

final class SystemMonitorCardViewTests: XCTestCase {
    func testDiskBarColorThresholds() {
        // 未到紧张区间用绿色，接近写满才升级为告警色
        XCTAssertEqual(SystemMonitorCardView.diskBarColor(fraction: 0.0), .green)
        XCTAssertEqual(SystemMonitorCardView.diskBarColor(fraction: 0.5), .green)
        XCTAssertEqual(SystemMonitorCardView.diskBarColor(fraction: 0.7499), .green)
        XCTAssertEqual(SystemMonitorCardView.diskBarColor(fraction: 0.75), .orange)
        XCTAssertEqual(SystemMonitorCardView.diskBarColor(fraction: 0.8999), .orange)
        XCTAssertEqual(SystemMonitorCardView.diskBarColor(fraction: 0.90), .red)
        XCTAssertEqual(SystemMonitorCardView.diskBarColor(fraction: 1.0), .red)
    }

    func testDiskBarColorFallsBackToGreenForNonFiniteFraction() {
        XCTAssertEqual(SystemMonitorCardView.diskBarColor(fraction: .nan), .green)
        XCTAssertEqual(SystemMonitorCardView.diskBarColor(fraction: .infinity), .green)
    }

    func testBreakdownMutualExclusion() {
        var expanded: BreakdownKind? = nil

        // Initial state
        XCTAssertNil(expanded)
        
        // Click CPU -> expands CPU
        SystemMonitorCardView.toggleBreakdown(kind: .cpu, current: &expanded)
        XCTAssertEqual(expanded, .cpu)
        
        // Click Memory -> mutually closes CPU and expands Memory
        SystemMonitorCardView.toggleBreakdown(kind: .memory, current: &expanded)
        XCTAssertEqual(expanded, .memory)
        
        // Click Memory again -> collapses to nil
        SystemMonitorCardView.toggleBreakdown(kind: .memory, current: &expanded)
        XCTAssertNil(expanded)
        
        // Click CPU -> expands CPU
        SystemMonitorCardView.toggleBreakdown(kind: .cpu, current: &expanded)
        XCTAssertEqual(expanded, .cpu)
        
        // Click CPU again -> collapses to nil
        SystemMonitorCardView.toggleBreakdown(kind: .cpu, current: &expanded)
        XCTAssertNil(expanded)

        // Click Network -> expands Network
        SystemMonitorCardView.toggleBreakdown(kind: .network, current: &expanded)
        XCTAssertEqual(expanded, .network)

        // Click CPU -> mutually closes Network and expands CPU
        SystemMonitorCardView.toggleBreakdown(kind: .cpu, current: &expanded)
        XCTAssertEqual(expanded, .cpu)

        // Click Network -> mutually closes CPU and expands Network
        SystemMonitorCardView.toggleBreakdown(kind: .network, current: &expanded)
        XCTAssertEqual(expanded, .network)

        // Click Memory -> mutually closes Network and expands Memory
        SystemMonitorCardView.toggleBreakdown(kind: .memory, current: &expanded)
        XCTAssertEqual(expanded, .memory)

        // Click Network -> mutually closes Memory and expands Network
        SystemMonitorCardView.toggleBreakdown(kind: .network, current: &expanded)
        XCTAssertEqual(expanded, .network)

        // Click Network again -> collapses to nil
        SystemMonitorCardView.toggleBreakdown(kind: .network, current: &expanded)
        XCTAssertNil(expanded)
    }

    func testCalculatePeak() {
        // Empty arrays
        XCTAssertEqual(SystemMonitorCardView.calculatePeak(downHistory: [], upHistory: []), 1024)
        XCTAssertEqual(SystemMonitorCardView.calculatePeak(downHistory: [], upHistory: [], minPeak: 512), 512)

        // All zero
        XCTAssertEqual(SystemMonitorCardView.calculatePeak(downHistory: [0, 0, 0], upHistory: [0, 0]), 1024)
        XCTAssertEqual(SystemMonitorCardView.calculatePeak(downHistory: [0], upHistory: [0], minPeak: 200), 200)

        // Normal values
        XCTAssertEqual(SystemMonitorCardView.calculatePeak(downHistory: [2048, 512], upHistory: [100, 4096]), 4096)
        XCTAssertEqual(SystemMonitorCardView.calculatePeak(downHistory: [8192, 1024], upHistory: [500, 2048]), 8192)
        XCTAssertEqual(SystemMonitorCardView.calculatePeak(downHistory: [200, 500], upHistory: [100, 300]), 1024)
        XCTAssertEqual(SystemMonitorCardView.calculatePeak(downHistory: [200, 500], upHistory: [100, 300], minPeak: 100), 500)

        // Finite check (NaN, infinity, negative values)
        XCTAssertEqual(SystemMonitorCardView.calculatePeak(downHistory: [Double.nan, Double.infinity, 2048], upHistory: [-Double.infinity, 500]), 2048)
        XCTAssertEqual(SystemMonitorCardView.calculatePeak(downHistory: [Double.nan], upHistory: [Double.infinity]), 1024)
        XCTAssertEqual(SystemMonitorCardView.calculatePeak(downHistory: [-100, -200], upHistory: [-50]), 1024)
        XCTAssertEqual(SystemMonitorCardView.calculatePeak(downHistory: [100], upHistory: [200], minPeak: Double.nan), 1024)
        XCTAssertEqual(SystemMonitorCardView.calculatePeak(downHistory: [100], upHistory: [200], minPeak: Double.infinity), 1024)
    }

    func testViewInitialization() {
        let defaultView = SystemMonitorCardView()
        XCTAssertNotNil(defaultView)

        let appState = AppState()
        let viewWithAppState = SystemMonitorCardView(appState: appState)
        XCTAssertNotNil(viewWithAppState)
    }

    func testToggleBreakdownWithBattery() {
        var expanded: BreakdownKind? = nil
        SystemMonitorCardView.toggleBreakdown(kind: .battery, current: &expanded)
        XCTAssertEqual(expanded, .battery)

        SystemMonitorCardView.toggleBreakdown(kind: .network, current: &expanded)
        XCTAssertEqual(expanded, .network)

        SystemMonitorCardView.toggleBreakdown(kind: .cpu, current: &expanded)
        XCTAssertEqual(expanded, .cpu)

        SystemMonitorCardView.toggleBreakdown(kind: .battery, current: &expanded)
        XCTAssertEqual(expanded, .battery)

        SystemMonitorCardView.toggleBreakdown(kind: .battery, current: &expanded)
        XCTAssertNil(expanded)
    }

    func testCardLanguageFollowsSystemResolution() {
        let appState = AppState()
        let original = appState.language
        defer { appState.language = original }

        // 跟随系统时，卡片传给 I18n 的语言必须是解析后的真实语言代码，
        // 不能把 rawValue "system" 直接当 languageCode 用（会兜底成英文）
        appState.language = .system
        let view = SystemMonitorCardView(appState: appState)
        XCTAssertNotEqual(view.language, "system")
        XCTAssertEqual(view.language, I18n.resolveLanguage(.system))

        // 显式语言直接透传
        appState.language = .en
        XCTAssertEqual(SystemMonitorCardView(appState: appState).language, "en")
    }

    func testBatterySymbolName() {
        // 充电中测试
        XCTAssertEqual(SystemMonitorCardView.batterySymbolName(chargePercent: 95, isCharging: true, externalConnected: true), "battery.100.bolt")
        XCTAssertEqual(SystemMonitorCardView.batterySymbolName(chargePercent: 60, isCharging: true, externalConnected: true), "battery.75.bolt")
        XCTAssertEqual(SystemMonitorCardView.batterySymbolName(chargePercent: 15, isCharging: true, externalConnected: true), "battery.25.bolt")

        // 放电中测试
        XCTAssertEqual(SystemMonitorCardView.batterySymbolName(chargePercent: 95, isCharging: false, externalConnected: false), "battery.100")
        XCTAssertEqual(SystemMonitorCardView.batterySymbolName(chargePercent: 60, isCharging: false, externalConnected: false), "battery.75")
        XCTAssertEqual(SystemMonitorCardView.batterySymbolName(chargePercent: 35, isCharging: false, externalConnected: false), "battery.50")
        XCTAssertEqual(SystemMonitorCardView.batterySymbolName(chargePercent: 15, isCharging: false, externalConnected: false), "battery.25")
        XCTAssertEqual(SystemMonitorCardView.batterySymbolName(chargePercent: 0, isCharging: false, externalConnected: false), "battery.0")
    }
}
