import Foundation
import SwiftUI

@MainActor
final class ClamshellManager: ObservableObject {
    static let shared = ClamshellManager()
    
    @Published var isEnabledGlobally: Bool = false
    @Published var isExternallyEnabled: Bool = false
    
    @AppStorage("enableClamshellMode") private var enableClamshellMode = false
    
    private init() {}
    
    func syncWithSystem() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        task.arguments = ["-g"]
        let pipe = Pipe()
        task.standardOutput = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                let isAlreadyDisabled = output.range(of: "SleepDisabled\\s+1", options: .regularExpression) != nil
                
                self.isEnabledGlobally = isAlreadyDisabled
                
                if isAlreadyDisabled {
                    self.enableClamshellMode = true
                    if !UserDefaults.standard.bool(forKey: "didModifySleepDisabled") {
                        self.isExternallyEnabled = true
                    }
                } else {
                    self.enableClamshellMode = false
                    self.isExternallyEnabled = false
                    UserDefaults.standard.set(false, forKey: "didModifySleepDisabled")
                }
            }
        } catch {
            print("Failed to check pmset: \(error)")
        }
    }
    
    func setClamshellMode(enabled: Bool) {
        if enabled {
            let success = SudoersManager.pmsetDisableSleep(true)
            if success {
                self.enableClamshellMode = true
                self.isEnabledGlobally = true
                self.isExternallyEnabled = false
                UserDefaults.standard.set(true, forKey: "didModifySleepDisabled")
            }
        } else {
            let success = SudoersManager.pmsetDisableSleep(false)
            if success {
                self.enableClamshellMode = false
                self.isEnabledGlobally = false
                self.isExternallyEnabled = false
                UserDefaults.standard.set(false, forKey: "didModifySleepDisabled")
            }
        }
    }
    
    func restoreOnQuit() {
        if UserDefaults.standard.bool(forKey: "didModifySleepDisabled") {
            _ = SudoersManager.pmsetDisableSleep(false)
            UserDefaults.standard.set(false, forKey: "didModifySleepDisabled")
        }
    }
}
