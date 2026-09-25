import Foundation

/// 启动卷的容量读数。
///
/// 「可用」与「可清除」是两个不同口径：`availableBytes` 是系统愿意为重要用途
/// 腾出来的空间，`purgeableBytes` 是其中需要靠清理缓存 / 本地快照才能兑现的部分。
/// 界面把两者分开展示，用户才能判断空间是真的紧张还是只是缓存占着。
public struct DiskReading: Equatable, Sendable {
    public var volumeName: String
    public var fileSystem: String
    public var isInternal: Bool
    public var totalBytes: UInt64
    public var usedBytes: UInt64
    public var availableBytes: UInt64
    public var purgeableBytes: UInt64
    public var usedFraction: Double

    public init(volumeName: String,
                fileSystem: String,
                isInternal: Bool,
                totalBytes: UInt64,
                usedBytes: UInt64,
                availableBytes: UInt64,
                purgeableBytes: UInt64,
                usedFraction: Double) {
        self.volumeName = volumeName
        self.fileSystem = fileSystem
        self.isInternal = isInternal
        self.totalBytes = totalBytes
        self.usedBytes = usedBytes
        self.availableBytes = availableBytes
        self.purgeableBytes = purgeableBytes
        self.usedFraction = usedFraction
    }
}

public enum DiskSampler {
    /// 由原始容量数值推导读数。与磁盘读取分离，便于对裁剪边界做单元测试。
    ///
    /// APFS 的多个容量口径并非严格包含关系：容器共享空间、本地快照与缓存会让
    /// 「重要用途可用量」高于「裸空闲量」，反过来在快照异常或只读卷上也可能更低。
    /// 可用量取两者较大值，语义是「现在真正能写进去多少」—— 若能写字节数低于
    /// 裸空闲量，界面就会在一个尚有 40 GB 空闲的磁盘上显示「35 GB 可用」。
    /// 可清除量随之定义为可用量与裸空闲量之差，因此恒定满足
    /// `可用 = 立即空闲 + 可清除`，用户同时看到这两个数字时可以自行验算。
    public static func reading(volumeName: String,
                               fileSystem: String,
                               isInternal: Bool,
                               totalBytes: UInt64,
                               rawFreeBytes: UInt64,
                               importantFreeBytes: UInt64) -> DiskReading? {
        guard totalBytes > 0 else { return nil }

        let rawFree = min(rawFreeBytes, totalBytes)
        let importantFree = min(importantFreeBytes, totalBytes)

        let available = max(importantFree, rawFree)
        let used = totalBytes - rawFree

        return DiskReading(volumeName: volumeName,
                           fileSystem: fileSystem,
                           isInternal: isInternal,
                           totalBytes: totalBytes,
                           usedBytes: used,
                           availableBytes: available,
                           purgeableBytes: available - rawFree,
                           usedFraction: Double(used) / Double(totalBytes))
    }

    /// 读取启动卷（`/`）的容量。
    ///
    /// 只取启动卷：系统盘始终存在且始终可写，因此不必处理外置盘拔除、只读卷
    /// 无法查询重要用途可用量等分支。
    public static func sampleBootVolume() -> DiskReading? {
        let url = URL(fileURLWithPath: "/")
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeLocalizedNameKey,
            .volumeNameKey,
            .volumeIsInternalKey,
        ]

        guard let values = try? url.resourceValues(forKeys: keys),
              let total = positive(values.volumeTotalCapacity) else { return nil }

        let rawFree = positive(values.volumeAvailableCapacity) ?? 0
        // 重要用途可用量查询失败时退回裸空闲量：宁可少报可清除空间，
        // 也不能凭空许诺用户清理之后就能拿到更多的空间
        let importantFree = positive(values.volumeAvailableCapacityForImportantUsage) ?? rawFree
        let name = values.volumeLocalizedName ?? values.volumeName ?? url.lastPathComponent

        return reading(volumeName: name,
                       fileSystem: fileSystemLabel(),
                       isInternal: values.volumeIsInternal ?? true,
                       totalBytes: total,
                       rawFreeBytes: rawFree,
                       importantFreeBytes: importantFree)
    }

    /// 挂载点记录的文件系统类型名，如 `apfs`，转为界面展示的大写形式
    private static func fileSystemLabel() -> String {
        var fs = statfs()
        guard statfs("/", &fs) == 0 else { return "" }

        let capacity = MemoryLayout.size(ofValue: fs.f_fstypename)
        let name = withUnsafePointer(to: &fs.f_fstypename) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: capacity) {
                String(cString: $0)
            }
        }
        return name.uppercased()
    }

    private static func positive(_ value: Int?) -> UInt64? {
        guard let value, value > 0 else { return nil }
        return UInt64(value)
    }

    private static func positive(_ value: Int64?) -> UInt64? {
        guard let value, value > 0 else { return nil }
        return UInt64(value)
    }
}
