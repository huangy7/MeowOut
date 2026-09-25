import XCTest
@testable import MeowOut

final class DiskSamplerTests: XCTestCase {
    private let gib: UInt64 = 1024 * 1024 * 1024

    // MARK: - Capacity arithmetic

    func testReadingMatchesReportedCapacity() {
        // 与「磁盘使用」面板的实测值一致：494 GB 容量，60 GB 可用，29 GB 可清除
        let reading = DiskSampler.reading(volumeName: "Macintosh HD",
                                          fileSystem: "APFS",
                                          isInternal: true,
                                          totalBytes: 494 * gib,
                                          rawFreeBytes: 30 * gib,
                                          importantFreeBytes: 60 * gib)

        XCTAssertEqual(reading?.volumeName, "Macintosh HD")
        XCTAssertEqual(reading?.fileSystem, "APFS")
        XCTAssertEqual(reading?.isInternal, true)
        XCTAssertEqual(reading?.totalBytes, 494 * gib)
        XCTAssertEqual(reading?.usedBytes, 464 * gib)
        XCTAssertEqual(reading?.availableBytes, 60 * gib)
        XCTAssertEqual(reading?.purgeableBytes, 30 * gib)
        XCTAssertEqual(reading?.usedFraction ?? 0, 464.0 / 494.0, accuracy: 0.0001)
    }

    func testAvailableFallsBackToRawFreeWhenImportantFreeIsLower() {
        // 快照异常或只读卷上，重要用途可用量可能低于裸空闲量。
        // 此时可清除量为 0，可用量退回裸空闲量，而不是在尚有 40 GB
        // 空闲的磁盘上显示「35 GB 可用」
        let reading = DiskSampler.reading(volumeName: "Data",
                                          fileSystem: "APFS",
                                          isInternal: true,
                                          totalBytes: 100 * gib,
                                          rawFreeBytes: 40 * gib,
                                          importantFreeBytes: 35 * gib)

        XCTAssertEqual(reading?.purgeableBytes, 0)
        XCTAssertEqual(reading?.availableBytes, 40 * gib)
        XCTAssertEqual(reading?.usedBytes, 60 * gib)
    }

    func testUsedIsZeroWhenRawFreeExceedsTotal() {
        let reading = DiskSampler.reading(volumeName: "Weird",
                                          fileSystem: "APFS",
                                          isInternal: false,
                                          totalBytes: 100 * gib,
                                          rawFreeBytes: 150 * gib,
                                          importantFreeBytes: 150 * gib)

        XCTAssertEqual(reading?.usedBytes, 0)
        XCTAssertEqual(reading?.usedFraction, 0)
    }

    func testAvailableAndPurgeableClampToTotal() {
        let total = 100 * gib
        let rawFree = 20 * gib
        let reading = DiskSampler.reading(volumeName: "Bogus",
                                          fileSystem: "HFS",
                                          isInternal: true,
                                          totalBytes: total,
                                          rawFreeBytes: rawFree,
                                          importantFreeBytes: 500 * gib)

        XCTAssertEqual(reading?.availableBytes, total)
        XCTAssertEqual(reading?.usedBytes, 80 * gib)
        // 可用 = 立即空闲 + 可清除，界面同时展示这两个数字时用户会这样验算
        XCTAssertEqual(reading?.availableBytes, rawFree + (reading?.purgeableBytes ?? 0))
        XCTAssertEqual(reading?.purgeableBytes, 80 * gib)
    }

    func testAvailableAlwaysEqualsRawFreePlusPurgeable() throws {
        let cases: [(total: UInt64, rawFree: UInt64, importantFree: UInt64)] = [
            (494, 30, 60),
            (100, 40, 35),
            (100, 20, 500),
            (100, 0, 100),
            (100, 100, 100),
        ]

        for c in cases {
            let reading = try XCTUnwrap(DiskSampler.reading(volumeName: "V",
                                                            fileSystem: "APFS",
                                                            isInternal: true,
                                                            totalBytes: c.total * gib,
                                                            rawFreeBytes: c.rawFree * gib,
                                                            importantFreeBytes: c.importantFree * gib))
            let rawFree = min(c.rawFree, c.total) * gib
            XCTAssertEqual(reading.availableBytes,
                           rawFree + reading.purgeableBytes,
                           "可用量应等于立即空闲量加可清除量，输入 \(c)")
        }
    }

    func testUsedFractionStaysWithinUnitRangeForMessyInput() throws {
        let cases: [(total: UInt64, rawFree: UInt64, importantFree: UInt64)] = [
            (100, 0, 0),
            (100, 100, 100),
            (100, 50, 500),
            (100, 500, 20),
        ]

        for c in cases {
            let reading = DiskSampler.reading(volumeName: "V",
                                              fileSystem: "APFS",
                                              isInternal: true,
                                              totalBytes: c.total * gib,
                                              rawFreeBytes: c.rawFree * gib,
                                              importantFreeBytes: c.importantFree * gib)
            let fraction = try XCTUnwrap(reading?.usedFraction)
            XCTAssertGreaterThanOrEqual(fraction, 0)
            XCTAssertLessThanOrEqual(fraction, 1)
        }
    }

    func testReadingIsNilWhenTotalIsZero() {
        // 容量不可读时整行隐藏，而不是显示 0 GB / 0 GB
        let reading = DiskSampler.reading(volumeName: "Unreadable",
                                          fileSystem: "APFS",
                                          isInternal: true,
                                          totalBytes: 0,
                                          rawFreeBytes: 0,
                                          importantFreeBytes: 0)

        XCTAssertNil(reading)
    }

    // MARK: - Boot volume integration

    func testSampleBootVolumeReadsTheLiveRootVolume() throws {
        let value = try XCTUnwrap(DiskSampler.sampleBootVolume())

        XCTAssertFalse(value.volumeName.isEmpty)
        XCTAssertFalse(value.fileSystem.isEmpty)
        XCTAssertGreaterThan(value.totalBytes, 0)
        XCTAssertLessThanOrEqual(value.usedBytes, value.totalBytes)
        XCTAssertLessThanOrEqual(value.availableBytes, value.totalBytes)
        XCTAssertGreaterThanOrEqual(value.usedFraction, 0)
        XCTAssertLessThanOrEqual(value.usedFraction, 1)
    }
}
