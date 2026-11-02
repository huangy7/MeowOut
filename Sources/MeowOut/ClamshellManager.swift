import Foundation
import SwiftUI
import IOKit.pwr_mgt

@MainActor
final class ClamshellManager: ObservableObject {
    static let shared = ClamshellManager()
    
    /// 系统底层是否处于 SleepDisabled 状态
    @Published var isEnabledGlobally: Bool = false
    /// 是否由外部其他程序设置了 SleepDisabled
    @Published var isExternallyEnabled: Bool = false
    /// 当前是否由 MeowOut 激活了合盖不休眠
    @Published var isClamshellActive: Bool = false
    /// 免密权限是否已就绪
    @Published var isConfigured: Bool = false
    
    /// 用户是否开启了合盖后继续运行的偏好
    @AppStorage("enableClamshellMode") var isClamshellPreferred: Bool = false
    
    private init() {
        self.isConfigured = SudoersManager.isConfigured()
        syncWithSystem()
    }
    
    /// 同步当前系统底层实际电源配置与免密状态
    func syncWithSystem() {
        self.isConfigured = SudoersManager.isConfigured()
        
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        task.arguments = ["-g"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        
        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            if let output = String(data: data, encoding: .utf8) {
                let isAlreadyDisabled = output.range(of: #"SleepDisabled\s+1"#, options: .regularExpression) != nil
                self.isEnabledGlobally = isAlreadyDisabled
                
                let didModify = UserDefaults.standard.bool(forKey: "didModifySleepDisabled")
                if isAlreadyDisabled {
                    if didModify {
                        self.isClamshellActive = true
                        self.isExternallyEnabled = false
                    } else {
                        self.isClamshellActive = false
                        self.isExternallyEnabled = true
                    }
                } else {
                    self.isClamshellActive = false
                    self.isExternallyEnabled = false
                    UserDefaults.standard.set(false, forKey: "didModifySleepDisabled")
                }
            }
        } catch {
            print("Failed to check pmset: \(error)")
        }
    }
    
    /// 激活系统底层合盖不休眠
    @discardableResult
    func enableClamshell() -> Bool {
        // 如果外部已启用了合盖不休眠，MeowOut 直接协同工作，不强行标记为独占修改，防止后续误关用户的全局设定
        if isEnabledGlobally && isExternallyEnabled {
            self.isClamshellActive = true
            return true
        }
        
        guard SudoersManager.isConfigured() else {
            return false
        }
        
        let success = SudoersManager.pmsetDisableSleep(true)
        if success {
            self.isEnabledGlobally = true
            self.isClamshellActive = true
            self.isExternallyEnabled = false
            UserDefaults.standard.set(true, forKey: "didModifySleepDisabled")
            return true
        }
        return false
    }
    
    /// 取消合盖不休眠并恢复系统默认休眠行为
    @discardableResult
    func disableClamshell(triggerSleepIfLidClosed: Bool = true) -> Bool {
        // 如果最初是外部设置的，MeowOut 不去破坏用户的原始外部设置
        if isExternallyEnabled {
            self.isClamshellActive = false
            return true
        }
        
        let success = SudoersManager.pmsetDisableSleep(false)
        if success {
            self.isEnabledGlobally = false
            self.isClamshellActive = false
            self.isExternallyEnabled = false
            UserDefaults.standard.set(false, forKey: "didModifySleepDisabled")
            
            if triggerSleepIfLidClosed {
                Self.sleepIfLidAlreadyClosed()
            }
            return true
        }
        return false
    }
    
    /// 供设置面板切换合盖偏好时调用
    func setClamshellMode(enabled: Bool) {
        self.isClamshellPreferred = enabled
        if enabled {
            // 如果防休眠会话当前处于运行状态，立即应用合盖策略
            if PowerAssertionService.shared.isKeepingAwake {
                _ = enableClamshell()
            }
        } else {
            if isClamshellActive {
                _ = disableClamshell()
            }
        }
    }
    
    /// 检测机盖是否处于合上状态
    static func lidClosed() -> Bool? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        return IORegistryEntryCreateCFProperty(
            service,
            "AppleClamshellState" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? Bool
    }
    
    /// 检测当前是否有连接外部显示器
    static func hasExternalDisplay() -> Bool {
        var onlineDisplays = [CGDirectDisplayID](repeating: 0, count: 16)
        var displayCount: UInt32 = 0
        guard CGGetOnlineDisplayList(16, &onlineDisplays, &displayCount) == .success else { return false }
        return (0..<Int(displayCount)).contains { CGDisplayIsBuiltin(onlineDisplays[$0]) == 0 }
    }
    
    /// 当系统关闭合盖不休眠且当前机盖已闭合（且无外接显示器桌面模式）时，补发休眠事件，避免在闭盖收纳状态下持续发热耗电
    static func sleepIfLidAlreadyClosed() {
        // 若外接了显示器，合盖工作属于系统合法的合盖桌面模式（Closed-Display Mode），绝不强制休眠
        guard lidClosed() == true, !hasExternalDisplay() else { return }
        let rootDomain = IOPMFindPowerManagement(kIOMainPortDefault)
        guard rootDomain != 0 else { return }
        _ = IOPMSleepSystem(rootDomain)
        IOServiceClose(rootDomain)
    }
    
    /// 恢复上次异常退出残留的底层设置
    func restoreOnLaunch() {
        if UserDefaults.standard.bool(forKey: "didModifySleepDisabled") {
            _ = SudoersManager.pmsetDisableSleep(false)
            UserDefaults.standard.set(false, forKey: "didModifySleepDisabled")
            Self.sleepIfLidAlreadyClosed()
        }
        syncWithSystem()
    }
    
    /// 退出时确保还原系统睡眠行为
    func restoreOnQuit() {
        if UserDefaults.standard.bool(forKey: "didModifySleepDisabled") {
            _ = SudoersManager.pmsetDisableSleep(false)
            UserDefaults.standard.set(false, forKey: "didModifySleepDisabled")
            Self.sleepIfLidAlreadyClosed()
        }
        isClamshellActive = false
        if !isExternallyEnabled {
            isEnabledGlobally = false
        }
    }
}
