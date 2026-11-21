import CoreGraphics
import Darwin
import Foundation
import IOKit

/// 内置显示器亮度读写与合盖硬件状态桥接。
/// 仅操作内置屏幕（CGDisplayIsBuiltin != 0），不影响外接显示器；
/// 若当前设备无内置屏或系统移除 DisplayServices 私有符号，安全降级返回 nil / false。
enum LidDisplayDimmer {
    private typealias GetBrightnessFn = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightnessFn = @convention(c) (UInt32, Float) -> Int32

    private static let displayServicesHandle = dlopen(
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
        RTLD_LAZY
    )

    private static let getBrightnessFn: GetBrightnessFn? = symbol(
        displayServicesHandle,
        "DisplayServicesGetBrightness"
    )
    private static let setBrightnessFn: SetBrightnessFn? = symbol(
        displayServicesHandle,
        "DisplayServicesSetBrightness"
    )

    private static func symbol<T>(_ handle: UnsafeMutableRawPointer?, _ name: String) -> T? {
        guard let handle, let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }

    /// 通过 `CGGetOnlineDisplayList` 定位内置屏（合盖后内置屏可能离开 active 列表但仍在 online 列表中）。
    static func builtInDisplayID() -> CGDirectDisplayID? {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(16, &ids, &count) == .success else { return nil }
        return ids.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
    }

    /// 是否存在外接显示器（在线显示器中存在非内置屏）。
    static func hasExternalDisplay() -> Bool? {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success else { return nil }
        guard count > 0 else { return false }

        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return nil }
        let flags = ids.prefix(Int(count)).map { CGDisplayIsBuiltin($0) != 0 }
        return KeepAwakeSupport.hasExternalDisplay(builtInFlags: flags)
    }

    /// 读取内置屏当前亮度（0.0...1.0）；无法识别面板或读取失败返回 nil，绝不返回假 0。
    static func currentBrightness() -> Double? {
        guard let id = builtInDisplayID(), let getBrightnessFn else { return nil }
        var value: Float = 0
        guard getBrightnessFn(id, &value) == 0 else { return nil }
        return Double(value)
    }

    /// 写入内置屏亮度；仅当找到面板且系统调用返回 0 时返回 true。
    @discardableResult
    static func setBrightness(_ value: Double) -> Bool {
        guard let id = builtInDisplayID(), let setBrightnessFn else { return false }
        let clamped = Float(min(max(value, 0.0), 1.0))
        return setBrightnessFn(id, clamped) == 0
    }

    /// 读取 `IOPMrootDomain` 的 `AppleClamshellState`，判断当前笔记本盖子是否已合上。
    static func lidClosed() -> Bool? {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPMrootDomain")
        )
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        return IORegistryEntryCreateCFProperty(
            service,
            "AppleClamshellState" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? Bool
    }

    /// 读取 `IOPMrootDomain` 的 `AppleClamshellCausesSleep`，判断系统当前策略是否允许合盖休眠。
    static func systemClamshellCausesSleep() -> Bool? {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPMrootDomain")
        )
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        return IORegistryEntryCreateCFProperty(
            service,
            "AppleClamshellCausesSleep" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? Bool
    }
}
