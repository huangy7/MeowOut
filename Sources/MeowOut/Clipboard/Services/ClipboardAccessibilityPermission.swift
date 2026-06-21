import ApplicationServices
import AppKit
import Foundation

public enum ClipboardAccessibilityPermission {
    public static func openSettingsAfterPrompt(
        requestPrompt: () -> Void = requestAuthorizationPrompt,
        openSettings: () -> Void = openAccessibilitySettings
    ) {
        requestPrompt()
        openSettings()
    }

    public static func requestAuthorizationPrompt() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    public static func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }

        NSWorkspace.shared.open(url)
    }
}
