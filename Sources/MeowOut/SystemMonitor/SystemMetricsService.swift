import AppKit
import Combine
import Darwin
import Foundation
import IOKit

// MARK: - Models

public enum BreakdownKind: String, CaseIterable, Codable, Equatable, Sendable {
    case cpu
    case memory
    case network
    case battery
    case disk
}

public struct SystemMetricsSnapshot: Equatable, Sendable {
    public var cpuUsage: Double // 0.0 ... 1.0
    public var memoryUsed: UInt64 // bytes
    public var memoryTotal: UInt64 // bytes
    public var uptimeSeconds: Int
    public var netDownBytesPerSec: Double
    public var netUpBytesPerSec: Double
    public var netDownHistory: [Double]
    public var netUpHistory: [Double]
    public var battery: BatteryReading
    /// 启动卷容量读数。容量不可读时为 nil，对应界面整行隐藏。
    public var disk: DiskReading?

    public var memoryUsagePercentage: Double {
        guard memoryTotal > 0 else { return 0 }
        return Double(memoryUsed) / Double(memoryTotal)
    }

    public init(
        cpuUsage: Double = 0,
        memoryUsed: UInt64 = 0,
        memoryTotal: UInt64 = 0,
        uptimeSeconds: Int = 0,
        netDownBytesPerSec: Double = 0,
        netUpBytesPerSec: Double = 0,
        netDownHistory: [Double] = [],
        netUpHistory: [Double] = [],
        battery: BatteryReading = BatteryReading(),
        disk: DiskReading? = nil
    ) {
        self.cpuUsage = cpuUsage
        self.memoryUsed = memoryUsed
        self.memoryTotal = memoryTotal
        self.uptimeSeconds = uptimeSeconds
        self.netDownBytesPerSec = netDownBytesPerSec
        self.netUpBytesPerSec = netUpBytesPerSec
        self.netDownHistory = netDownHistory
        self.netUpHistory = netUpHistory
        self.battery = battery
        self.disk = disk
    }

    public mutating func appendNetworkHistory(down: Double, up: Double, maxCount: Int = 30) {
        netDownBytesPerSec = down
        netUpBytesPerSec = up
        guard maxCount > 0 else {
            netDownHistory.removeAll()
            netUpHistory.removeAll()
            return
        }
        netDownHistory.append(down)
        if netDownHistory.count > maxCount {
            netDownHistory.removeFirst(netDownHistory.count - maxCount)
        }
        netUpHistory.append(up)
        if netUpHistory.count > maxCount {
            netUpHistory.removeFirst(netUpHistory.count - maxCount)
        }
    }
}

public struct ProcessUsageItem: Identifiable, Equatable {
    public var id: pid_t
    public var name: String
    public var icon: NSImage?
    public var cpuPercent: Double // e.g. 18.5 for 18.5%
    public var memoryBytes: UInt64

    public var canActivate: Bool {
        guard let app = NSRunningApplication(processIdentifier: id),
              app.activationPolicy == .regular,
              !app.isTerminated
        else { return false }
        return true
    }

    public func activate() {
        guard canActivate,
              let app = NSRunningApplication(processIdentifier: id)
        else { return }
        if #available(macOS 14.0, *) {
            if !app.activate(from: NSRunningApplication.current, options: []) {
                app.activate()
            }
        } else {
            app.activate(options: [.activateIgnoringOtherApps])
        }
    }

    public init(id: pid_t, name: String, icon: NSImage? = nil, cpuPercent: Double = 0, memoryBytes: UInt64 = 0) {
        self.id = id
        self.name = name
        self.icon = icon
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
    }

    public static func == (lhs: ProcessUsageItem, rhs: ProcessUsageItem) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.cpuPercent == rhs.cpuPercent && lhs.memoryBytes == rhs.memoryBytes
    }
}

// MARK: - SystemMetricsService

public final class SystemMetricsService: ObservableObject {
    public static let shared = SystemMetricsService()

    @Published public var snapshot = SystemMetricsSnapshot()
    @Published public var topCPUProcesses: [ProcessUsageItem] = []
    @Published public var topMemoryProcesses: [ProcessUsageItem] = []
    @Published public var topEnergyProcesses: [ProcessUsageItem] = []
    @Published public var isSamplingProcesses = false

    public struct CPUTicks: Equatable {
        public let busy: UInt64
        public let total: UInt64

        public init(busy: UInt64, total: UInt64) {
            self.busy = busy
            self.total = total
        }
    }

    private let queue = DispatchQueue(label: "com.meowout.systemmetrics", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var previousCPUTicks: CPUTicks?
    private let networkSampler = NetworkSampler()
    private let batterySampler = BatterySampler()
    private var netDownHistory: [Double] = []
    private var netUpHistory: [Double] = []
    
    // Per-PID CPU tracker for delta calculation
    private var previousProcessCpuSample: (time: Date, perPid: [pid_t: UInt64])?
    private var previousEnergySample: (time: Date, cpu: [pid_t: UInt64], gpu: [pid_t: Double])?
    private static var timebaseInfo: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    /// 动态链接 libsystem 中的 `responsibility_get_pid_responsible_for_pid`
    /// 将 Chrome Renderer, CLion Clangd 等辅助子进程聚合到主应用 PID 下
    private static let resolveResponsiblePid: (@convention(c) (pid_t) -> pid_t)? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2) /* RTLD_DEFAULT */,
                                 "responsibility_get_pid_responsible_for_pid")
        else { return nil }
        return unsafeBitCast(symbol, to: (@convention(c) (pid_t) -> pid_t).self)
    }()

    public static func responsiblePid(for pid: pid_t) -> pid_t {
        guard let resolve = resolveResponsiblePid else { return pid }
        let owner = resolve(pid)
        return owner > 0 ? owner : pid
    }

    public init() {
        self.previousCPUTicks = Self.readCPUTicks()
    }

    deinit {
        stop()
    }

    // MARK: - Formatting Helpers

    public static func formatSpeed(_ bytesPerSec: Double) -> String {
        guard bytesPerSec.isFinite && bytesPerSec >= 1024 else { return "0 KB/s" }
        let kb = bytesPerSec / 1024.0
        if kb < 1023.95 {
            return String(format: "%.1f KB/s", kb)
        }
        let mb = kb / 1024.0
        if mb < 1023.95 {
            return String(format: "%.1f MB/s", mb)
        }
        let gb = mb / 1024.0
        return String(format: "%.1f GB/s", gb)
    }

    public static func formatUptime(seconds: Int, language: String) -> String {
        let s = max(0, seconds)
        let isZh = language.lowercased().contains("zh")
        if s >= 86400 {
            let days = s / 86400
            let hours = (s % 86400) / 3600
            return isZh ? "已开机 \(days)天\(hours)时" : "Up \(days)d \(hours)h"
        } else if s >= 3600 {
            let hours = s / 3600
            let minutes = (s % 3600) / 60
            return isZh ? "已开机 \(hours)时\(minutes)分" : "Up \(hours)h \(minutes)m"
        } else {
            let minutes = s / 60
            return isZh ? "已开机 \(minutes)分" : "Up \(minutes)m"
        }
    }

    public static func formatBytes(_ bytes: UInt64) -> String {
        let gb = 1024.0 * 1024.0 * 1024.0
        let mb = 1024.0 * 1024.0
        let kb = 1024.0

        if bytes >= 1024 * 1024 * 1024 {
            return String(format: "%.1f GB", Double(bytes) / gb)
        } else if bytes >= 1024 * 1024 {
            return String(format: "%d MB", Int(Double(bytes) / mb))
        } else {
            return String(format: "%d KB", Int(Double(bytes) / kb))
        }
    }

    /// 磁盘容量格式化。
    ///
    /// 按十进制（10^9）换算，与 Finder、磁盘工具、关于本机 的读数保持一致 ——
    /// 同一块盘在这些系统工具里显示 494 GB，若改用 2^30 会显示成 460 GB，
    /// 用户对照时会认为读数有误。内存行沿用 `formatBytes` 的二进制换算不动：
    /// 系统对内存本来就按 2^30 报告，16 GiB 内存各处都显示「16 GB」。
    /// 按整数位展示，容量读数的小数位不携带信息，反而让整行更拥挤；
    /// TB 保留一位小数，1.5 TB 取整成「2 TB」会虚报容量。
    public static func formatDiskBytes(_ bytes: UInt64) -> String {
        let tb = 1_000_000_000_000.0
        let gb = 1_000_000_000.0
        let mb = 1_000_000.0
        let kb = 1_000.0
        let value = Double(bytes)

        if value >= tb {
            let tera = value / tb
            return String(format: tera.rounded() == tera ? "%.0f TB" : "%.1f TB", tera)
        }
        if value >= gb {
            return String(format: "%.0f GB", value / gb)
        }
        if value >= mb {
            return String(format: "%.0f MB", value / mb)
        }
        return String(format: "%.0f KB", value / kb)
    }

    public static func formatBatteryWatts(_ watts: Double?) -> String {
        guard let w = watts, w.isFinite, w >= 0 else { return "--" }
        if w == 0 { return "0W" }
        return String(format: "%.1fW", w)
    }

    public static func calculateUsage(previous: CPUTicks, current: CPUTicks) -> Double {
        guard current.total > previous.total else { return 0.0 }
        guard current.busy >= previous.busy else { return 0.0 }

        let busyDelta = Double(current.busy - previous.busy)
        let totalDelta = Double(current.total - previous.total)
        guard totalDelta > 0 else { return 0.0 }

        let usage = busyDelta / totalDelta
        return min(max(usage, 0.0), 1.0)
    }

    // MARK: - Kernel Sampling

    public static func readCPUTicks() -> CPUTicks? {
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        var cpuLoadInfo = host_cpu_load_info()
        let host = mach_host_self()
        defer {
            mach_port_deallocate(mach_task_self_, host)
        }

        let result = withUnsafeMutablePointer(to: &cpuLoadInfo) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics(host, HOST_CPU_LOAD_INFO, intPtr, &count)
            }
        }

        guard result == KERN_SUCCESS else { return nil }

        let user = UInt64(cpuLoadInfo.cpu_ticks.0)
        let system = UInt64(cpuLoadInfo.cpu_ticks.1)
        let idle = UInt64(cpuLoadInfo.cpu_ticks.2)
        let nice = UInt64(cpuLoadInfo.cpu_ticks.3)

        let busy = user + system + nice
        let total = busy + idle
        return CPUTicks(busy: busy, total: total)
    }

    /// 读取物理内存与已用内存（遵循 macOS 活动监视器计算方式）
    /// Memory Used = App Memory (internal - purgeable) + Wired Memory + Compressed
    public static func readMemory() -> (used: UInt64, total: UInt64) {
        let total = ProcessInfo.processInfo.physicalMemory
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        var vmStats = vm_statistics64()
        let host = mach_host_self()
        defer {
            mach_port_deallocate(mach_task_self_, host)
        }

        let result = withUnsafeMutablePointer(to: &vmStats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(host, HOST_VM_INFO64, intPtr, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return (used: 0, total: total)
        }

        let pageSize = UInt64(vm_kernel_page_size)
        
        // App 内存：内部页减去可清除页
        let internalPages = UInt64(vmStats.internal_page_count)
        let purgeablePages = UInt64(vmStats.purgeable_count)
        let appPages = internalPages >= purgeablePages ? (internalPages - purgeablePages) : 0
        let appBytes = appPages * pageSize
        
        // 联动内存与压缩内存
        let wiredBytes = UInt64(vmStats.wire_count) * pageSize
        let compressedBytes = UInt64(vmStats.compressor_page_count) * pageSize
        
        let used = appBytes + wiredBytes + compressedBytes
        return (used: min(used, total), total: total)
    }

    public static func readUptime() -> Int {
        var bootTime = timeval()
        var size = MemoryLayout<timeval>.size
        if sysctlbyname("kern.boottime", &bootTime, &size, nil, 0) == 0 {
            let boot = Double(bootTime.tv_sec) + (Double(bootTime.tv_usec) / 1_000_000.0)
            let elapsed = Date().timeIntervalSince1970 - boot
            return max(0, Int(elapsed))
        }
        return max(0, Int(ProcessInfo.processInfo.systemUptime))
    }

    public func readSnapshot() -> SystemMetricsSnapshot {
        let currentTicks = Self.readCPUTicks()
        var cpuUsage: Double = 0.0
        if let current = currentTicks, let previous = previousCPUTicks {
            cpuUsage = Self.calculateUsage(previous: previous, current: current)
        }
        if let current = currentTicks {
            previousCPUTicks = current
        }

        let mem = Self.readMemory()
        let uptime = Self.readUptime()
        let reading = networkSampler.sample()
        let battery = batterySampler.sample()
        // retain history from queue-protected history, then append new reading
        var newSnapshot = SystemMetricsSnapshot(
            cpuUsage: cpuUsage,
            memoryUsed: mem.used,
            memoryTotal: mem.total,
            uptimeSeconds: uptime,
            netDownBytesPerSec: reading.downBytesPerSec,
            netUpBytesPerSec: reading.upBytesPerSec,
            netDownHistory: netDownHistory,
            netUpHistory: netUpHistory,
            battery: battery,
            disk: DiskSampler.sampleBootVolume()
        )
        newSnapshot.appendNetworkHistory(down: reading.downBytesPerSec, up: reading.upBytesPerSec)
        netDownHistory = newSnapshot.netDownHistory
        netUpHistory = newSnapshot.netUpHistory
        return newSnapshot
    }

    // MARK: - Process-level Kernel Footprint & CPU Sampling

    /// 读取单个进程的物理占用内存 (Physical Footprint)
    /// 与活动监视器的 Memory 列严格一致
    public static func physicalFootprint(of pid: pid_t) -> UInt64? {
        var info = rusage_info_current()
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rebound in
                proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, rebound)
            }
        }
        guard status == 0, info.ri_phys_footprint > 0 else { return nil }
        return info.ri_phys_footprint
    }

    /// 读取单个进程的累计 CPU 纳秒数
    private static func cpuTimeNanoseconds(of pid: pid_t) -> UInt64? {
        var info = rusage_info_current()
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rebound in
                proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, rebound)
            }
        }
        guard status == 0 else { return nil }
        let total = info.ri_user_time.addingReportingOverflow(info.ri_system_time)
        guard !total.overflow else { return nil }
        let numer = UInt64(timebaseInfo.numer)
        let denom = UInt64(timebaseInfo.denom)
        guard denom > 0 else { return total.partialValue }
        let multiplied = total.partialValue.multipliedReportingOverflow(by: numer)
        guard !multiplied.overflow else { return total.partialValue }
        return multiplied.partialValue / denom
    }

    /// 枚举所有运行中的 PID
    private static func allRunningPids() -> [pid_t] {
        let estimatedCount = max(1, Int(proc_listallpids(nil, 0)))
        var pids = [pid_t](repeating: 0, count: estimatedCount + 64)
        let count = pids.withUnsafeMutableBytes { buffer in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count))
        }
        guard count > 0 else { return [] }
        return Array(pids.prefix(Int(count))).filter { $0 > 0 }
    }

    private static func gpuTimePerPid() -> [pid_t: Double] {
        var perPid: [pid_t: Double] = [:]

        var accelIterator = io_iterator_t()
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("IOAccelerator"),
                                           &accelIterator) == kIOReturnSuccess else { return perPid }
        defer { IOObjectRelease(accelIterator) }

        var accelerator = IOIteratorNext(accelIterator)
        while accelerator != 0 {
            defer {
                IOObjectRelease(accelerator)
                accelerator = IOIteratorNext(accelIterator)
            }

            var clients = io_iterator_t()
            guard IORegistryEntryGetChildIterator(accelerator, kIOServicePlane, &clients) == kIOReturnSuccess
            else { continue }
            defer { IOObjectRelease(clients) }

            var client = IOIteratorNext(clients)
            while client != 0 {
                defer {
                    IOObjectRelease(client)
                    client = IOIteratorNext(clients)
                }

                guard let creatorRef = IORegistryEntryCreateCFProperty(
                          client, "IOUserClientCreator" as CFString, kCFAllocatorDefault, 0),
                      let creator = creatorRef.takeRetainedValue() as? String,
                      let pid = Self.pid(fromCreator: creator)
                else { continue }

                guard let usageRef = IORegistryEntryCreateCFProperty(
                          client, "AppUsage" as CFString, kCFAllocatorDefault, 0),
                      let usage = usageRef.takeRetainedValue() as? [[String: Any]]
                else { continue }

                for entry in usage {
                    if let time = entry["accumulatedGPUTime"] as? Double {
                        perPid[pid, default: 0] += time
                    } else if let time = entry["accumulatedGPUTime"] as? Int64 {
                        perPid[pid, default: 0] += Double(time)
                    } else if let time = entry["accumulatedGPUTime"] as? Int {
                        perPid[pid, default: 0] += Double(time)
                    } else if let time = entry["accumulatedGPUTime"] as? UInt64 {
                        perPid[pid, default: 0] += Double(time)
                    } else if let time = entry["accumulatedGPUTime"] as? NSNumber {
                        perPid[pid, default: 0] += time.doubleValue
                    }
                }
            }
        }
        return perPid
    }

    private static func pid(fromCreator creator: String) -> pid_t? {
        guard creator.hasPrefix("pid ") else { return nil }
        let digits = creator.dropFirst(4).prefix { $0.isNumber }
        return pid_t(digits)
    }

    public func sampleTopProcesses(kind: BreakdownKind) -> [ProcessUsageItem] {
        let pids = Self.allRunningPids()
        let now = Date()

        switch kind {
        case .memory:
            // 聚合物理内存：将子进程 (Chrome Renderer 等) 归属到主负责应用
            var memoryTotals: [pid_t: UInt64] = [:]
            for pid in pids {
                guard let fp = Self.physicalFootprint(of: pid) else { continue }
                let owner = Self.responsiblePid(for: pid)
                memoryTotals[owner, default: 0] += fp
            }

            let sorted = memoryTotals.sorted { $0.value > $1.value }.prefix(5)
            return sorted.map { owner, bytes in
                let (name, icon) = Self.appInfo(for: owner)
                return ProcessUsageItem(
                    id: owner,
                    name: name,
                    icon: icon,
                    cpuPercent: 0,
                    memoryBytes: bytes
                )
            }

        case .cpu:
            // 采集当前 CPU 时间快照
            var currentSample: [pid_t: UInt64] = [:]
            for pid in pids {
                if let ns = Self.cpuTimeNanoseconds(of: pid) {
                    currentSample[pid] = ns
                }
            }

            defer {
                self.previousProcessCpuSample = (time: now, perPid: currentSample)
            }

            guard let previous = self.previousProcessCpuSample else {
                // 首次采样，暂存基准快照，返回按历史累计时间排序的列表
                var initialTotals: [pid_t: UInt64] = [:]
                for (pid, ns) in currentSample {
                    let owner = Self.responsiblePid(for: pid)
                    initialTotals[owner, default: 0] += ns
                }
                let sorted = initialTotals.sorted { $0.value > $1.value }.prefix(5)
                return sorted.map { owner, _ in
                    let (name, icon) = Self.appInfo(for: owner)
                    return ProcessUsageItem(
                        id: owner,
                        name: name,
                        icon: icon,
                        cpuPercent: 0,
                        memoryBytes: 0
                    )
                }
            }

            let elapsedSec = now.timeIntervalSince(previous.time)
            guard elapsedSec > 0.1 else { return self.topCPUProcesses }

            var cpuTotals: [pid_t: UInt64] = [:]
            for (pid, currNs) in currentSample {
                guard let prevNs = previous.perPid[pid], currNs >= prevNs else { continue }
                let deltaNs = currNs - prevNs
                guard deltaNs > 0 else { continue }
                let owner = Self.responsiblePid(for: pid)
                cpuTotals[owner, default: 0] += deltaNs
            }

            let sorted = cpuTotals.sorted { $0.value > $1.value }.prefix(5)
            return sorted.map { owner, deltaNs in
                let (name, icon) = Self.appInfo(for: owner)
                let percent = (Double(deltaNs) / 1_000_000_000.0 / elapsedSec) * 100.0
                return ProcessUsageItem(
                    id: owner,
                    name: name,
                    icon: icon,
                    cpuPercent: round(percent * 10) / 10,
                    memoryBytes: 0
                )
            }
        case .battery:
            var currentCpuSample: [pid_t: UInt64] = [:]
            for pid in pids {
                if let ns = Self.cpuTimeNanoseconds(of: pid) {
                    currentCpuSample[pid] = ns
                }
            }
            let currentGpuSample = Self.gpuTimePerPid()

            guard let previous = self.previousEnergySample else {
                self.previousEnergySample = (time: now, cpu: currentCpuSample, gpu: currentGpuSample)
                // 能耗属于速率型衍生指标，依赖时间窗口内的工作量差值率（Rate of Work / Delta Time）进行评估。
                // 首次采样建立基准时，在后台工作队列休眠最小有效观测窗口（150ms）后自调用获取即时差值，
                // 避免前台首次展开因无基准而呈现空状态。
                Thread.sleep(forTimeInterval: 0.15)
                return self.sampleTopProcesses(kind: .battery)
            }

            let elapsedSec = now.timeIntervalSince(previous.time)
            guard elapsedSec > 0.1 else { return self.topEnergyProcesses }

            defer {
                self.previousEnergySample = (time: now, cpu: currentCpuSample, gpu: currentGpuSample)
            }

            var energyTotals: [pid_t: Double] = [:]
            let allPids = Set(currentCpuSample.keys).union(currentGpuSample.keys)

            for pid in allPids {
                var cpuPercent = 0.0
                if let currNs = currentCpuSample[pid],
                   let prevNs = previous.cpu[pid],
                   currNs >= prevNs {
                    let deltaNs = currNs - prevNs
                    cpuPercent = (Double(deltaNs) / 1_000_000_000.0 / elapsedSec) * 100.0
                }

                var gpuPercent = 0.0
                if let currGpu = currentGpuSample[pid],
                   let prevGpu = previous.gpu[pid],
                   currGpu >= prevGpu {
                    let deltaGpu = currGpu - prevGpu
                    gpuPercent = (deltaGpu / (elapsedSec * 1_000_000_000.0)) * 100.0
                }

                let energyScore = cpuPercent + gpuPercent
                guard energyScore > 0 else { continue }

                let owner = Self.responsiblePid(for: pid)
                energyTotals[owner, default: 0] += energyScore
            }

            let filtered = energyTotals.filter { $0.value >= 0.5 }
            let sorted = filtered.sorted { $0.value > $1.value }.prefix(5)
            return sorted.map { owner, score in
                let (name, icon) = Self.appInfo(for: owner)
                return ProcessUsageItem(
                    id: owner,
                    name: name,
                    icon: icon,
                    cpuPercent: round(score * 10) / 10,
                    memoryBytes: 0
                )
            }

        case .network, .disk:
            return []
        }
    }

    /// 提取 PID 对应的应用名称与图标（优先匹配运行中的常规应用）
    private static func appInfo(for pid: pid_t) -> (name: String, icon: NSImage?) {
        if let app = NSRunningApplication(processIdentifier: pid),
           let locName = app.localizedName, !locName.isEmpty {
            return (locName, app.icon)
        }

        // 尝试根据 PID 读取进程名称
        var buffer = [CChar](repeating: 0, count: 256)
        if proc_name(pid, &buffer, UInt32(buffer.count)) > 0 {
            let procName = String(cString: buffer).trimmingCharacters(in: .whitespaces)
            if !procName.isEmpty {
                return (procName, NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil))
            }
        }

        return ("pid \(pid)", nil)
    }

    // MARK: - Lifecycle & Public Controls

    public func start(interval: TimeInterval = 2.0) {
        stop()
        refresh()

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            self?.refresh()
        }
        timer.resume()
        self.timer = timer
    }

    public func stop() {
        timer?.cancel()
        timer = nil
    }

    public func refresh() {
        queue.async { [weak self] in
            guard let self = self else { return }
            let newSnapshot = self.readSnapshot()
            DispatchQueue.main.async {
                self.snapshot = newSnapshot
            }
        }
    }

    public func refreshTopProcesses(kind: BreakdownKind) {
        guard !isSamplingProcesses else { return }
        DispatchQueue.main.async {
            self.isSamplingProcesses = true
        }
        queue.async { [weak self] in
            guard let self = self else { return }
            let items = self.sampleTopProcesses(kind: kind)
            DispatchQueue.main.async {
                switch kind {
                case .cpu:
                    self.topCPUProcesses = items
                case .memory:
                    self.topMemoryProcesses = items
                case .battery:
                    self.topEnergyProcesses = items
                case .network, .disk:
                    break
                }
                self.isSamplingProcesses = false
            }
        }
    }
}
