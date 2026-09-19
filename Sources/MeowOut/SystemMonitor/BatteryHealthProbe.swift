import Darwin
import Foundation

/// Reads the smoothed battery “Maximum Capacity” value shown by macOS System
/// Settings. IORegistry's full/design-capacity ratio is useful as a fallback,
/// but it does not always match Apple's health calculation.
final class BatteryHealthProbe: @unchecked Sendable {
    static let shared = BatteryHealthProbe()

    private let queue = DispatchQueue(label: "com.meowout.battery-health", qos: .utility)
    private let lock = NSLock()
    private var cached: Int?
    private var lastRefresh: TimeInterval = -.greatestFiniteMagnitude
    private var running = false
    private let refreshInterval: TimeInterval = 1800

    private init() {}

    var percent: Int? {
        lock.lock()
        defer { lock.unlock() }
        return cached
    }

    /// Starts a refresh without blocking the system metrics sampling queue.
    func refreshIfStale() {
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        guard !running, now - lastRefresh >= refreshInterval else {
            lock.unlock()
            return
        }
        running = true
        lastRefresh = now
        lock.unlock()

        queue.async { [weak self] in
            guard let self else { return }
            let value = Self.read()
            self.lock.lock()
            self.cached = value
            self.running = false
            self.lock.unlock()
        }
    }

    /// Parses the `sppower_battery_health_maximum_capacity` field from
    /// `system_profiler SPPowerDataType -json`. The field may be a string such
    /// as `"95%"` or a number and may be nested under `_items`.
    static func percent(fromSystemProfilerJSON data: Data) -> Int? {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return percent(in: root)
    }

    private static func read() -> Int? {
        let result = runSystemProfiler()
        guard result.status == 0 else { return nil }
        return percent(fromSystemProfilerJSON: result.output)
    }

    private static func runSystemProfiler() -> (status: Int32, output: Data) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPPowerDataType", "-json"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let output = OutputBuffer(limit: 1024 * 1024)
        let drained = DispatchSemaphore(value: 0)
        let reader = pipe.fileHandleForReading
        reader.readabilityHandler = { handle in
            let chunk = handle.availableData
            if !chunk.isEmpty {
                output.append(chunk)
            } else {
                drained.signal()
            }
        }

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }

        do {
            try process.run()
        } catch {
            reader.readabilityHandler = nil
            try? reader.close()
            return (-1, Data())
        }

        let timedOut = finished.wait(timeout: .now() + 5) != .success
        var didFinish = !timedOut
        if timedOut {
            process.terminate()
            didFinish = finished.wait(timeout: .now() + 0.5) == .success
            if !didFinish {
                kill(process.processIdentifier, SIGKILL)
                _ = finished.wait(timeout: .now() + 0.5)
            }
        }

        // Let the readability handler receive the final bytes before closing
        // the descriptor. The output is capped and the pipe stays drained.
        _ = drained.wait(timeout: .now() + 0.2)
        reader.readabilityHandler = nil
        try? reader.close()

        return (timedOut || !didFinish ? -1 : process.terminationStatus, output.value())
    }

    private static func percent(in value: Any) -> Int? {
        if let dict = value as? [String: Any] {
            if let raw = dict["sppower_battery_health_maximum_capacity"],
               let value = percent(fromRawValue: raw) {
                return value
            }
            for (key, raw) in dict {
                let normalized = key.lowercased().filter(\.isLetter)
                if normalized.contains("maximumcapacity"),
                   let value = percent(fromRawValue: raw) {
                    return value
                }
            }
            for raw in dict.values {
                if let value = percent(in: raw) {
                    return value
                }
            }
        } else if let array = value as? [Any] {
            for raw in array {
                if let value = percent(in: raw) {
                    return value
                }
            }
        }
        return nil
    }

    private static func percent(fromRawValue raw: Any) -> Int? {
        let value: Int?
        switch raw {
        case is Bool:
            value = nil
        case let raw as Int:
            value = raw
        case let raw as NSNumber:
            value = raw.intValue
        case let raw as String:
            guard let range = raw.range(of: #"[0-9]{1,3}"#, options: .regularExpression) else {
                value = nil
                break
            }
            value = Int(raw[range])
        default:
            value = nil
        }
        guard let value, (1...100).contains(value) else { return nil }
        return value
    }
}

private final class OutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private var data = Data()

    init(limit: Int) {
        self.limit = max(0, limit)
    }

    func append(_ chunk: Data) {
        lock.lock()
        defer { lock.unlock() }
        let available = max(0, limit - data.count)
        if available > 0 {
            data.append(chunk.prefix(available))
        }
    }

    func value() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}
