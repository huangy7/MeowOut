import AppKit
import Foundation

/// 管理合盖不休眠所需的受限 sudoers 免密规则与 `pmset disablesleep` 串行调用。
enum SudoersManager {
    static let rulePath = "/etc/sudoers.d/meowout-clamshell"

    /// 序列化所有 `pmset` 读写与探测，避免并发写入或探测把刚恢复的 `0` 覆盖回 `1`。
    private static let sleepStateQueue = DispatchQueue(label: "com.meowout.pmset-state")
    /// 管理员授权降级恢复期间挂起探测（仅在 `sleepStateQueue` 上读写）。
    private static var sleepStateProbeSuspensions = 0

    /// 执行外部命令并收集退出码与标准输出。
    private static func runProcess(_ executable: String, _ arguments: [String]) -> (status: Int32, output: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            let output = String(data: data, encoding: .utf8) ?? ""
            return (task.terminationStatus, output)
        } catch {
            return (-1, "")
        }
    }

    /// 读取当前系统 `pmset -g` 中的 `SleepDisabled` 状态。
    static func readSleepDisabledState() -> (ok: Bool, disabled: Bool) {
        let report = runProcess("/usr/bin/pmset", ["-g"])
        guard report.status == 0 else { return (false, false) }
        return (true, SudoersSupport.sleepDisabled(inPmsetOutput: report.output))
    }

    /// 通过实际重放当前 `SleepDisabled` 状态验证免密路径是否真正可用。
    /// 不改变系统现有状态，并规避部分 macOS 上 `sudo -l` 报可用但实际执行仍索要密码的问题。
    static func isConfigured() -> Bool {
        sleepStateQueue.sync {
            guard sleepStateProbeSuspensions == 0 else { return false }
            let state = readSleepDisabledState()
            guard state.ok else { return false }
            return pmsetDisableSleepOnQueue(state.disabled)
        }
    }

    /// 请求一次管理员密码，写入基于数字 UID 的受限 sudoers 规则并通过 `visudo -c -f` 校验。
    static func install(
        prompt: String = "授权 MeowOut 在防休眠期间合盖保持运行",
        completion: @escaping (Bool) -> Void
    ) {
        let rule = SudoersSupport.clamshellRule(uid: getuid())
        let command = "mkdir -p /etc/sudoers.d && chmod 0755 /etc/sudoers.d && echo '\(rule)' > \(rulePath) && chmod 0440 \(rulePath) && /usr/sbin/visudo -c -f \(rulePath) || { rm -f \(rulePath); exit 1; }"

        runAdminCommand(command, prompt: prompt) { ok in
            let verified = ok && isConfigured()
            DispatchQueue.main.async {
                completion(verified)
            }
        }
    }

    /// 同步切换 `pmset disablesleep`（排空此前排队写入，适用于 App 退出时同步恢复）。
    @discardableResult
    static func pmsetDisableSleep(_ on: Bool) -> Bool {
        sleepStateQueue.sync {
            pmsetDisableSleepOnQueue(on)
        }
    }

    /// 异步按请求顺序切换 `pmset disablesleep`（不阻塞主线程）。
    static func pmsetDisableSleep(_ on: Bool, completion: @escaping (Bool) -> Void) {
        sleepStateQueue.async {
            let ok = pmsetDisableSleepOnQueue(on)
            completion(ok)
        }
    }

    /// 免密恢复失败时的管理员授权兜底：先挂起探测并检查当前是否已为正常状态，
    /// 仅当仍处于 `SleepDisabled 1` 且调用方仍允许继续时才弹管理员密码恢复 `0`。
    static func restoreSleepWithAuthorization(
        prompt: String,
        shouldProceed: @escaping () -> Bool,
        completion: @escaping (Bool) -> Void
    ) {
        sleepStateQueue.async {
            sleepStateProbeSuspensions += 1
            let finish: (Bool) -> Void = { ok in
                sleepStateQueue.async {
                    sleepStateProbeSuspensions = max(0, sleepStateProbeSuspensions - 1)
                    completion(ok)
                }
            }

            let state = readSleepDisabledState()
            if state.ok, !state.disabled {
                finish(true)
                return
            }

            DispatchQueue.main.async {
                guard shouldProceed() else {
                    finish(false)
                    return
                }
                runAdminCommand("/usr/bin/pmset disablesleep 0", prompt: prompt, completion: finish)
            }
        }
    }

    private static func pmsetDisableSleepOnQueue(_ on: Bool) -> Bool {
        runProcess("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "disablesleep", on ? "1" : "0"]).status == 0
    }

    private static func runAdminCommand(
        _ command: String,
        prompt: String,
        completion: @escaping (Bool) -> Void
    ) {
        let escapedCommand = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let escapedPrompt = prompt
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let scriptSource = "do shell script \"\(escapedCommand)\" with administrator privileges with prompt \"\(escapedPrompt)\""

        // 在派发后台任务前在主线程异步激活应用，避免跨线程 sync 引发潜在死锁
        if Thread.isMainThread {
            NSApp.activate(ignoringOtherApps: true)
        } else {
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
            }
        }

        DispatchQueue.global(qos: .userInitiated).async {
            Thread.sleep(forTimeInterval: 0.12)

            let result = runProcess("/usr/bin/osascript", ["-e", scriptSource])
            completion(result.status == 0)
        }
    }
}
