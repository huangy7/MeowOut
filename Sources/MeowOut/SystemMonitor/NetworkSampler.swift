import Darwin
import Foundation

public struct NetworkCounters: Equatable {
    public var received: UInt64
    public var sent: UInt64

    public init(received: UInt64 = 0, sent: UInt64 = 0) {
        self.received = received
        self.sent = sent
    }
}

public struct NetworkReading: Equatable {
    public var downBytesPerSec: Double
    public var upBytesPerSec: Double

    public init(downBytesPerSec: Double = 0, upBytesPerSec: Double = 0) {
        self.downBytesPerSec = downBytesPerSec
        self.upBytesPerSec = upBytesPerSec
    }
}

public final class NetworkSampler {
    private let lock = NSLock()
    private var previous: (counters: NetworkCounters, time: TimeInterval)?
    private let counterReader: () -> NetworkCounters?
    private static let maxGap: TimeInterval = 10.0

    public init(counterReader: @escaping () -> NetworkCounters? = NetworkSampler.readCounters) {
        self.counterReader = counterReader
    }

    public func sample(now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> NetworkReading {
        guard let counters = counterReader() else {
            return NetworkReading()
        }

        lock.lock()
        defer { lock.unlock() }

        let prev = previous
        previous = (counters, now)

        guard let prev = prev, now > prev.time, now - prev.time <= Self.maxGap else {
            return NetworkReading()
        }

        let elapsed = now - prev.time
        guard elapsed > 0 else { return NetworkReading() }

        let downDelta = counters.received >= prev.counters.received ? Double(counters.received - prev.counters.received) : 0
        let upDelta = counters.sent >= prev.counters.sent ? Double(counters.sent - prev.counters.sent) : 0

        let downRate = downDelta / elapsed
        let upRate = upDelta / elapsed

        return NetworkReading(downBytesPerSec: downRate, upBytesPerSec: upRate)
    }

    public static func parseCounters(from raw: UnsafeRawBufferPointer) -> NetworkCounters {
        var result = NetworkCounters()
        guard let _ = raw.baseAddress else { return result }
        let length = raw.count
        var offset = 0
        let headerSize = MemoryLayout<if_msghdr>.size
        let ifm2Size = MemoryLayout<if_msghdr2>.size

        while offset + headerSize <= length {
            let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
            let messageLength = Int(header.ifm_msglen)
            guard messageLength > 0, offset + messageLength <= length else { break }

            if header.ifm_type == RTM_IFINFO2 {
                if offset + ifm2Size <= length, messageLength >= ifm2Size {
                    let ifm2 = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    let flags = Int32(ifm2.ifm_flags)
                    if (flags & IFF_LOOPBACK) == 0 {
                        result.received &+= ifm2.ifm_data.ifi_ibytes
                        result.sent &+= ifm2.ifm_data.ifi_obytes
                    }
                }
            }
            offset += messageLength
        }
        return result
    }

    public static func readCounters() -> NetworkCounters? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, 6, nil, &length, nil, 0) == 0, length > 0 else {
            return nil
        }

        let allocatedLength = length + 4096
        var actualLength = allocatedLength
        var buffer = [UInt8](repeating: 0, count: allocatedLength)
        guard sysctl(&mib, 6, &buffer, &actualLength, nil, 0) == 0 else {
            return nil
        }

        return buffer.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return NetworkCounters() }
            let validBuffer = UnsafeRawBufferPointer(start: base, count: min(actualLength, allocatedLength))
            return parseCounters(from: validBuffer)
        }
    }
}
