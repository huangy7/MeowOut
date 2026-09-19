import Darwin
import XCTest
@testable import MeowOut

final class NetworkSamplerTests: XCTestCase {
    func testReadInterfaceCountersReturnsValidOrNil() {
        let counters = NetworkSampler.readCounters()
        if let counters = counters {
            XCTAssertGreaterThanOrEqual(counters.received, 0)
            XCTAssertGreaterThanOrEqual(counters.sent, 0)
        }
    }

    func testSampleDeltaCalculation() {
        let c1 = NetworkCounters(received: 1_000_000, sent: 500_000)
        let c2 = NetworkCounters(received: 1_500_000, sent: 600_000)
        
        var counterIndex = 0
        let fakeReader: () -> NetworkCounters? = {
            if counterIndex == 0 {
                counterIndex += 1
                return c1
            } else {
                return c2
            }
        }
        
        let sampler = NetworkSampler(counterReader: fakeReader)
        
        // First sample establishes baseline, rates should be 0
        let r1 = sampler.sample(now: 100.0)
        XCTAssertEqual(r1.downBytesPerSec, 0.0)
        XCTAssertEqual(r1.upBytesPerSec, 0.0)
        
        // Second sample after 2.0s
        let r2 = sampler.sample(now: 102.0)
        XCTAssertEqual(r2.downBytesPerSec, 250_000.0, accuracy: 0.1) // 500KB / 2s
        XCTAssertEqual(r2.upBytesPerSec, 50_000.0, accuracy: 0.1)   // 100KB / 2s
    }

    func testSampleResetsOnLargeGap() {
        let c1 = NetworkCounters(received: 1_000_000, sent: 500_000)
        let c2 = NetworkCounters(received: 5_000_000, sent: 2_000_000)
        
        var counterIndex = 0
        let fakeReader: () -> NetworkCounters? = {
            if counterIndex == 0 {
                counterIndex += 1
                return c1
            } else {
                return c2
            }
        }
        
        let sampler = NetworkSampler(counterReader: fakeReader)
        _ = sampler.sample(now: 100.0)
        
        // Gap > 10.0s (e.g. system sleep/wake)
        let r2 = sampler.sample(now: 115.0)
        XCTAssertEqual(r2.downBytesPerSec, 0.0)
        XCTAssertEqual(r2.upBytesPerSec, 0.0)
    }

    func testParseCountersExtractsDataAndFiltersLoopback() {
        var if1 = if_msghdr2()
        if1.ifm_msglen = u_short(MemoryLayout<if_msghdr2>.size)
        if1.ifm_type = u_char(RTM_IFINFO2)
        if1.ifm_flags = 0
        if1.ifm_data.ifi_ibytes = 1_000_000
        if1.ifm_data.ifi_obytes = 500_000

        var if2Loopback = if_msghdr2()
        if2Loopback.ifm_msglen = u_short(MemoryLayout<if_msghdr2>.size)
        if2Loopback.ifm_type = u_char(RTM_IFINFO2)
        if2Loopback.ifm_flags = Int32(IFF_LOOPBACK)
        if2Loopback.ifm_data.ifi_ibytes = 99_999_999
        if2Loopback.ifm_data.ifi_obytes = 88_888_888

        var otherMsg = if_msghdr()
        otherMsg.ifm_msglen = u_short(MemoryLayout<if_msghdr>.size)
        otherMsg.ifm_type = u_char(RTM_NEWADDR)

        var buffer = [UInt8]()
        withUnsafeBytes(of: &if1) { buffer.append(contentsOf: $0) }
        withUnsafeBytes(of: &if2Loopback) { buffer.append(contentsOf: $0) }
        withUnsafeBytes(of: &otherMsg) { buffer.append(contentsOf: $0) }

        let counters = buffer.withUnsafeBytes { raw in
            NetworkSampler.parseCounters(from: raw)
        }

        XCTAssertEqual(counters.received, 1_000_000)
        XCTAssertEqual(counters.sent, 500_000)
    }

    func testParseCountersMalformedOrEmptyBuffer() {
        let emptyBytes = [UInt8]()
        let emptyCounters = emptyBytes.withUnsafeBytes { raw in
            NetworkSampler.parseCounters(from: raw)
        }
        XCTAssertEqual(emptyCounters, NetworkCounters(received: 0, sent: 0))

        // Truncated buffer smaller than headerSize
        let truncatedBytes: [UInt8] = [1, 2, 3]
        let truncatedCounters = truncatedBytes.withUnsafeBytes { raw in
            NetworkSampler.parseCounters(from: raw)
        }
        XCTAssertEqual(truncatedCounters, NetworkCounters(received: 0, sent: 0))

        // Buffer where messageLength is 0 (prevents infinite loop)
        var zeroLenMsg = if_msghdr()
        zeroLenMsg.ifm_msglen = 0
        zeroLenMsg.ifm_type = u_char(RTM_IFINFO2)
        var zeroLenBytes = [UInt8]()
        withUnsafeBytes(of: &zeroLenMsg) { zeroLenBytes.append(contentsOf: $0) }
        let zeroLenCounters = zeroLenBytes.withUnsafeBytes { raw in
            NetworkSampler.parseCounters(from: raw)
        }
        XCTAssertEqual(zeroLenCounters, NetworkCounters(received: 0, sent: 0))
    }

    func testSampleCounterResets() {
        let c1 = NetworkCounters(received: 1_000_000, sent: 500_000)
        let c2 = NetworkCounters(received: 100, sent: 50) // Interface reset or reboot
        let c3 = NetworkCounters(received: 500, sent: 250) // Subsequent sample

        var counterIndex = 0
        let fakeReader: () -> NetworkCounters? = {
            defer { counterIndex += 1 }
            switch counterIndex {
            case 0: return c1
            case 1: return c2
            default: return c3
            }
        }

        let sampler = NetworkSampler(counterReader: fakeReader)
        _ = sampler.sample(now: 100.0)

        // Second sample where counter dropped: delta should be 0, rates should be 0
        let r2 = sampler.sample(now: 101.0)
        XCTAssertEqual(r2.downBytesPerSec, 0.0)
        XCTAssertEqual(r2.upBytesPerSec, 0.0)

        // Third sample should calculate delta against c2
        let r3 = sampler.sample(now: 102.0)
        XCTAssertEqual(r3.downBytesPerSec, 400.0, accuracy: 0.1) // (500 - 100) / 1.0s
        XCTAssertEqual(r3.upBytesPerSec, 200.0, accuracy: 0.1)  // (250 - 50) / 1.0s
    }

    func testSampleNegativeOrZeroElapsedTime() {
        let c1 = NetworkCounters(received: 1_000_000, sent: 500_000)
        let c2 = NetworkCounters(received: 2_000_000, sent: 1_000_000)

        var counterIndex = 0
        let fakeReader: () -> NetworkCounters? = {
            if counterIndex == 0 {
                counterIndex += 1
                return c1
            } else {
                return c2
            }
        }

        let sampler = NetworkSampler(counterReader: fakeReader)
        _ = sampler.sample(now: 100.0)

        // Time moving backward (clock adjustment)
        let rBackward = sampler.sample(now: 95.0)
        XCTAssertEqual(rBackward.downBytesPerSec, 0.0)
        XCTAssertEqual(rBackward.upBytesPerSec, 0.0)

        // Time equal to previous sample
        let rZero = sampler.sample(now: 95.0)
        XCTAssertEqual(rZero.downBytesPerSec, 0.0)
        XCTAssertEqual(rZero.upBytesPerSec, 0.0)
    }
}
