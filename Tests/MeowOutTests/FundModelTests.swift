import XCTest
@testable import MeowOut

final class FundModelTests: XCTestCase {
    func testFundInfoCalculations() {
        let fund = FundInfo(
            code: "161725",
            name: "招商中证白酒指数(LOF)A",
            netValue: 1.2500,
            estimatedValue: 1.2650,
            changePercent: 1.20,
            navChangePercent: 0.85,
            updateTime: "2026-08-14 15:00",
            netValueDate: "2026-08-13"
        )

        let shares: Double = 1000.0
        let costPrice: Double = 1.1000

        // currentNav: estimatedValue (1.2650)
        XCTAssertEqual(fund.currentNav, 1.2650, accuracy: 0.001)

        // 持有市值: currentNav (1.2650) * 1000 = 1265
        XCTAssertEqual(fund.holdingAmount(shares: shares), 1265.0, accuracy: 0.001)

        // 实时持有收益: (1.2650 - 1.1000) * 1000 = 165.0
        XCTAssertEqual(fund.holdingGain(shares: shares, costPrice: costPrice), 165.0, accuracy: 0.001)

        // 实时持有收益率: (1.2650 - 1.1000) / 1.1000 * 100 = 15.0%
        XCTAssertEqual(fund.holdingGainRate(costPrice: costPrice), (1.2650 - 1.1) / 1.1 * 100, accuracy: 0.001)

        // 估算收益: baseNav = 1.2650 / (1 + 1.2 / 100) = 1.25
        // gain = (1.2650 - 1.25) * 1000 = 15.0
        let estGain = fund.estimatedGain(shares: shares)
        XCTAssertEqual(estGain, 15.0, accuracy: 0.01)
    }

    func testFundInfoEstimatedGainFallback() {
        let fund = FundInfo(
            code: "005827",
            name: "易方达蓝筹精选",
            netValue: 2.0000,
            estimatedValue: nil,
            changePercent: -1.50,
            navChangePercent: -0.5,
            updateTime: "2026-08-14 15:00",
            netValueDate: "2026-08-13"
        )

        let shares: Double = 500.0
        // Fallback: netValue * shares * changePercent / 100 = 2.0 * 500 * -1.5 / 100 = -15.0
        XCTAssertEqual(fund.estimatedGain(shares: shares), -15.0, accuracy: 0.001)
    }

    @MainActor
    func testFundConfigStoreCRUD() {
        let store = FundConfigStore.shared
        let originalConfigs = store.configs

        // Clean slate for test
        store.configs = []

        let config1 = FundConfig(code: "161725", shares: 1000, costPrice: 1.2)
        let config2 = FundConfig(code: "005827", shares: 500, costPrice: 2.3)

        store.add(config1)
        store.add(config2)
        XCTAssertEqual(store.configs.count, 2)
        XCTAssertEqual(store.codeList, "161725,005827")

        // Avoid duplicates
        store.add(config1)
        XCTAssertEqual(store.configs.count, 2)

        // Update
        store.update(code: "161725", shares: 1500, costPrice: 1.15)
        let updated = store.configs.first(where: { $0.code == "161725" })
        XCTAssertEqual(updated?.shares, 1500)
        XCTAssertEqual(updated?.costPrice, 1.15)

        // Reorder tests
        let config3 = FundConfig(code: "025733", shares: 200, costPrice: 0.8)
        store.add(config2)
        store.add(config3)
        // Current: [161725, 005827, 025733]
        XCTAssertEqual(store.codeList, "161725,005827,025733")

        // Move 025733 up
        store.moveUp(code: "025733")
        // Now: [161725, 025733, 005827]
        XCTAssertEqual(store.codeList, "161725,025733,005827")

        // Move 161725 down
        store.moveDown(code: "161725")
        // Now: [025733, 161725, 005827]
        XCTAssertEqual(store.codeList, "025733,161725,005827")

        // Remove
        store.remove(code: "005827")
        store.remove(code: "025733")
        XCTAssertEqual(store.configs.count, 1)
        XCTAssertEqual(store.codeList, "161725")

        // Restore
        store.configs = originalConfigs
        store.save()
    }

    func testBuiltInToolTypeFundSerialization() throws {
        let tool = QuickTool.builtIn(.fund)
        let data = try JSONEncoder().encode(tool)
        let decoded = try JSONDecoder().decode(QuickTool.self, from: data)

        if case .builtIn(let type) = decoded {
            XCTAssertEqual(type, .fund)
            XCTAssertEqual(type.icon, "📈")
        } else {
            XCTFail("Expected .builtIn(.fund)")
        }
    }

    @MainActor
    func testFundServiceRefreshIntegration() async {
        let store = FundConfigStore.shared
        let originalConfigs = store.configs

        store.configs = [
            FundConfig(code: "025733"),
            FundConfig(code: "021224")
        ]

        await FundService.shared.refresh()

        let funds = FundService.shared.funds
        print("Fetched funds count:", funds.count)
        for f in funds {
            print("Fund code:", f.code, "name:", f.name, "netValue:", f.netValue, "estValue:", String(describing: f.estimatedValue), "change%:", f.changePercent)
        }

        XCTAssertFalse(funds.isEmpty, "Funds should not be empty")
        if let f1 = funds.first(where: { $0.code == "025733" }) {
            XCTAssertNotEqual(f1.name, "025733", "Fund name should not be code")
            XCTAssertGreaterThan(f1.netValue, 0, "netValue should be > 0")
        }

        store.configs = originalConfigs
        store.save()
    }

    @MainActor
    func testFundConfigStoreExportAndImport() {
        let store = FundConfigStore.shared
        let originalConfigs = store.configs

        store.configs = [
            FundConfig(code: "161725", shares: 1000, costPrice: 1.25),
            FundConfig(code: "005827", shares: 500, costPrice: 2.10)
        ]

        // Test Export
        let exportedJSON = store.exportToJSONString()
        XCTAssertNotNil(exportedJSON)
        XCTAssertTrue(exportedJSON!.contains("161725"))
        XCTAssertTrue(exportedJSON!.contains("005827"))

        // Test Parse
        let parsed = FundConfigStore.parseConfigs(from: exportedJSON!)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.count, 2)

        // Test Import Replace
        let newConfigs = [
            FundConfig(code: "025733", shares: 300, costPrice: 0.95)
        ]
        let importedCount = store.importConfigs(newConfigs, mode: .replace)
        XCTAssertEqual(importedCount, 1)
        XCTAssertEqual(store.configs.count, 1)
        XCTAssertEqual(store.configs.first?.code, "025733")

        // Test Import Merge
        let mergeConfigs = [
            FundConfig(code: "025733", shares: 500, costPrice: 1.00), // update
            FundConfig(code: "161725", shares: 200, costPrice: 1.30)  // append
        ]
        store.importConfigs(mergeConfigs, mode: .merge)
        XCTAssertEqual(store.configs.count, 2)
        let merged025733 = store.configs.first(where: { $0.code == "025733" })
        XCTAssertEqual(merged025733?.shares, 500)
        XCTAssertEqual(merged025733?.costPrice, 1.00)

        // Test Invalid Parse
        XCTAssertNil(FundConfigStore.parseConfigs(from: "invalid json string"))
        XCTAssertNil(FundConfigStore.parseConfigs(from: "[]"))

        // Restore
        store.configs = originalConfigs
        store.save()
    }
}
