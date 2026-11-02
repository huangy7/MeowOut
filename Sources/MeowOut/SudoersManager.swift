import Foundation
import AppKit

enum SudoersManager {
    static let rulePath = "/etc/sudoers.d/meowout-clamshell"

    /// 检查免密提权规则是否已正确安装且生效
    static func isConfigured() -> Bool {
        if canListDisableSleep(value: "1") && canListDisableSleep(value: "0") {
            return true
        }
        // 如果 -l 校验受策略限制，直接尝试免密执行状态探针
        return probeDisableSleep()
    }

    private static func canListDisableSleep(value: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        task.arguments = ["-n", "-l", "/usr/bin/pmset", "disablesleep", value]
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// 通过重设当前已有状态来探测免密通道是否畅通，不改动任何系统预期行为
    private static func probeDisableSleep() -> Bool {
        let checkTask = Process()
        checkTask.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        checkTask.arguments = ["-g"]
        let pipe = Pipe()
        checkTask.standardOutput = pipe
        checkTask.standardError = Pipe()
        do {
            try checkTask.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            checkTask.waitUntilExit()
            guard checkTask.terminationStatus == 0 else { return false }
            let output = String(data: data, encoding: .utf8) ?? ""
            let isAlreadyDisabled = output.range(of: #"SleepDisabled\s+1"#, options: .regularExpression) != nil
            return pmsetDisableSleep(isAlreadyDisabled)
        } catch {
            return false
        }
    }

    /// 请求管理员权限以部署免密 sudoers 规则文件
    static func install(prompt: String? = nil, completion: @escaping (Bool) -> Void) {
        // 使用 uid（#uid 格式）作为用户标识，规避 SSO 或特殊字符用户名在 shell 及 sudoers 解析中的潜在异常
        let rule = "#\(getuid()) ALL=(root) NOPASSWD: /usr/bin/pmset disablesleep 1, /usr/bin/pmset disablesleep 0"
        let command = "mkdir -p /etc/sudoers.d && chmod 0755 /etc/sudoers.d && echo '\(rule)' > \(rulePath) && chmod 0440 \(rulePath) && /usr/sbin/visudo -c -f \(rulePath) || { rm -f \(rulePath); exit 1; }"
        
        let escapedCommand = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let displayPrompt = prompt ?? "授权 MeowOut 在合盖时保持运行"
        let escapedPrompt = displayPrompt.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        
        let scriptSource = "do shell script \"\(escapedCommand)\" with administrator privileges with prompt \"\(escapedPrompt)\""
        
        // 在派发后台任务前，直接在当前线程（或主线程）激活应用，保证安全无死锁
        if Thread.isMainThread {
            NSApp.activate(ignoringOtherApps: true)
        } else {
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
            }
        }

        DispatchQueue.global(qos: .userInitiated).async {
            Thread.sleep(forTimeInterval: 0.12)
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", scriptSource]
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            
            do {
                try process.run()
                process.waitUntilExit()
                let success = process.terminationStatus == 0
                
                DispatchQueue.main.async {
                    completion(success && isConfigured())
                }
            } catch {
                DispatchQueue.main.async {
                    completion(false)
                }
            }
        }
    }
    
    /// 执行 pmset disablesleep 免密提权调用
    @discardableResult
    static func pmsetDisableSleep(_ on: Bool) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        task.arguments = ["-n", "/usr/bin/pmset", "disablesleep", on ? "1" : "0"]
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }
}
