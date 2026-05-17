import Foundation
import ServiceManagement
import Observation
import AppKit

@Observable
@MainActor
public final class LaunchManager {
    public static let shared = LaunchManager()

    // 强制声明一个可观察的属性，确保 UI 能响应变化
    public var isLaunchAtLoginEnabled: Bool = false

    private init() {
        refreshStatus()

        // 监听应用回到前台，自动刷新状态（防止用户在系统设置里改了，App 没反应）
        NotificationCenter.default.addObserver(forName: NSApplication.willBecomeActiveNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in
                self.refreshStatus()
            }
        }
    }

    public func refreshStatus() {
        // SMAppService.mainApp.status 可能不会实时通知 SwiftUI，所以我们手动拉取
        let status = SMAppService.mainApp.status
        self.isLaunchAtLoginEnabled = (status == .enabled)
    }

    public func toggleLaunchAtLogin(enabled: Bool) {
        // 1. 立即乐观更新 UI 状态，防止开关回弹
        self.isLaunchAtLoginEnabled = enabled

        // 2. 执行真实的系统注册/反注册
        Task {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Failed to update launch at login status: \(error)")
                // 如果失败了，再同步回真实的系统状态
                refreshStatus()
            }
        }
    }
}
