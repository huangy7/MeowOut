import Foundation
import AppKit

enum SudoersManager {
    static let rulePath = "/etc/sudoers.d/meowout-clamshell"

    /// Checks if the sudoers rule is correctly installed and functioning.
    static func isConfigured() -> Bool {
        return canListDisableSleep(value: "1") && canListDisableSleep(value: "0")
    }

    private static func canListDisableSleep(value: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        task.arguments = ["-n", "-l", "/usr/bin/pmset", "disablesleep", value]
        
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Prompts the user with an administrator dialog to install the sudoers rule.
    static func install(completion: @escaping (Bool) -> Void) {
        guard let user = NSUserName() as String?,
              user.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil else {
            completion(false)
            return
        }

        let rule = "\(user) ALL=(root) NOPASSWD: /usr/bin/pmset disablesleep 1, /usr/bin/pmset disablesleep 0"
        let command = "mkdir -p /etc/sudoers.d && chmod 0755 /etc/sudoers.d && echo '\(rule)' > \(rulePath) && chmod 0440 \(rulePath) && /usr/sbin/visudo -c -f \(rulePath) || { rm -f \(rulePath); exit 1; }"
        
        let escapedCommand = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let escapedPrompt = "授权 MeowOut 在合盖时保持运行".replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        
        let scriptSource = "do shell script \"\(escapedCommand)\" with administrator privileges with prompt \"\(escapedPrompt)\""
        
        DispatchQueue.global(qos: .userInitiated).async {
            // Bring app to front so prompt isn't hidden
            DispatchQueue.main.sync {
                NSApp.activate(ignoringOtherApps: true)
            }
            Thread.sleep(forTimeInterval: 0.12)
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", scriptSource]
            
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
    
    /// Executes pmset disablesleep command without a password prompt.
    @discardableResult
    static func pmsetDisableSleep(_ on: Bool) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        task.arguments = ["-n", "/usr/bin/pmset", "disablesleep", on ? "1" : "0"]
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }
}
