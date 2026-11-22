// Sources/MeowOut/Settings/ShortcutRecorderSupport.swift
import AppKit
import Carbon.HIToolbox
import KeyboardShortcuts

/// MeowOut 全部全局快捷键注册表：用于应用内冲突检测与友好文案提示。
enum AppShortcutRegistry {
    struct Entry: Equatable {
        let name: KeyboardShortcuts.Name
        let titleKey: String
    }

    static let allEntries: [Entry] = [
        Entry(name: .togglePanel, titleKey: "settings_tab_keydrop"),
        Entry(name: .toggleClipboardHistoryPanel, titleKey: "settings_tab_clipboard"),
        Entry(name: .toggleShelf, titleKey: "settings_tab_shelf"),
        Entry(name: .toggleLauncher, titleKey: "menu_quick_actions"),
        Entry(name: .toggleFundPanel, titleKey: "settings_tab_fund"),
        Entry(name: .toggleMemosQuickCapture, titleKey: "memos_settings_quick_capture"),
        Entry(name: .toggleMemosBrowserWindow, titleKey: "memos_settings_open_browser"),
    ]

    static func conflictingEntry(
        for shortcut: KeyboardShortcuts.Shortcut,
        excluding name: KeyboardShortcuts.Name,
        lookup: (KeyboardShortcuts.Name) -> KeyboardShortcuts.Shortcut? = { KeyboardShortcuts.getShortcut(for: $0) }
    ) -> Entry? {
        for entry in allEntries where entry.name != name {
            if lookup(entry.name) == shortcut {
                return entry
            }
        }
        return nil
    }
}

/// 快捷键胶囊显示格式化：按 Apple HIG 顺序（⌃ ⌥ ⇧ ⌘）加空格排版，Space 统一规范为英文。
enum ShortcutDisplayFormatter {
    private static let modifierSymbolCharacters: Set<Character> = ["⌃", "⌥", "⇧", "⌘"]

    static func modifierSymbols(from modifiers: NSEvent.ModifierFlags) -> [String] {
        var symbols: [String] = []
        if modifiers.contains(.control) { symbols.append("⌃") }
        if modifiers.contains(.option) { symbols.append("⌥") }
        if modifiers.contains(.shift) { symbols.append("⇧") }
        if modifiers.contains(.command) { symbols.append("⌘") }
        return symbols
    }

    static func format(shortcut: KeyboardShortcuts.Shortcut) -> String {
        let symbols = modifierSymbols(from: shortcut.modifiers)
        let keyTitle = extractKeyTitle(from: shortcut)
        if keyTitle.isEmpty {
            return symbols.joined(separator: " ")
        }
        if symbols.isEmpty {
            return keyTitle
        }
        return symbols.joined(separator: " ") + " " + keyTitle
    }

    static func formatLiveModifiers(_ modifiers: NSEvent.ModifierFlags) -> String {
        let symbols = modifierSymbols(from: modifiers)
        guard !symbols.isEmpty else { return "" }
        return symbols.joined(separator: " ") + " …"
    }

    private static func extractKeyTitle(from shortcut: KeyboardShortcuts.Shortcut) -> String {
        if shortcut.key == .space {
            return "Space"
        }
        let raw = "\(shortcut)"
        let stripped = String(raw.drop(while: { modifierSymbolCharacters.contains($0) }))
            .trimmingCharacters(in: .whitespaces)
        return stripped.isEmpty ? raw : stripped
    }
}

/// 录制期间按键意图分类。
enum ShortcutKeyAction: Equatable {
    case cancel
    case clear
    case moveFocus
    case requiresModifier
    case recordable
}

enum ShortcutInputValidator {
    private static let functionKeyCodes: Set<UInt16> = [
        UInt16(kVK_F1), UInt16(kVK_F2), UInt16(kVK_F3), UInt16(kVK_F4),
        UInt16(kVK_F5), UInt16(kVK_F6), UInt16(kVK_F7), UInt16(kVK_F8),
        UInt16(kVK_F9), UInt16(kVK_F10), UInt16(kVK_F11), UInt16(kVK_F12),
        UInt16(kVK_F13), UInt16(kVK_F14), UInt16(kVK_F15), UInt16(kVK_F16),
        UInt16(kVK_F17), UInt16(kVK_F18), UInt16(kVK_F19), UInt16(kVK_F20),
    ]

    static func isFunctionKeyCode(_ keyCode: UInt16) -> Bool {
        functionKeyCodes.contains(keyCode)
    }

    static func classify(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        isFunctionKey: Bool
    ) -> ShortcutKeyAction {
        let relevantModifiers = modifiers.intersection([.command, .option, .control, .shift])

        if keyCode == UInt16(kVK_Escape) {
            return .cancel
        }
        if (keyCode == UInt16(kVK_Delete) || keyCode == UInt16(kVK_ForwardDelete)), relevantModifiers.isEmpty {
            return .clear
        }
        if keyCode == UInt16(kVK_Tab), relevantModifiers.isEmpty {
            return .moveFocus
        }
        if relevantModifiers.isEmpty && !(isFunctionKey || isFunctionKeyCode(keyCode)) {
            return .requiresModifier
        }
        return .recordable
    }

    static func isDisallowedInSandbox(modifiers: NSEvent.ModifierFlags) -> Bool {
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        guard osVersion.majorVersion == 15,
              osVersion.minorVersion == 0 || osVersion.minorVersion == 1,
              ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil else {
            return false
        }
        guard modifiers.contains(.option) else { return false }
        return modifiers.isDisjoint(with: [.command, .control])
    }

    @MainActor
    static func conflictingMainMenuItemTitle(
        for shortcut: KeyboardShortcuts.Shortcut,
        in menu: NSMenu? = nil
    ) -> String? {
        guard let resolvedMenu = menu ?? NSApp.mainMenu else { return nil }
        let targetKey = ShortcutDisplayFormatter.format(shortcut: KeyboardShortcuts.Shortcut(
            carbonKeyCode: shortcut.carbonKeyCode,
            carbonModifiers: 0
        )).lowercased()
        let targetModifiers = shortcut.modifiers.intersection([.command, .option, .control, .shift])

        for item in resolvedMenu.items {
            if let submenu = item.submenu,
               let title = conflictingMainMenuItemTitle(for: shortcut, in: submenu) {
                return title
            }
            guard !item.keyEquivalent.isEmpty else { continue }
            let itemModifiers = item.keyEquivalentModifierMask.intersection([.command, .option, .control, .shift])
            if item.keyEquivalent.lowercased() == targetKey && itemModifiers == targetModifiers {
                return item.title
            }
        }
        return nil
    }
}

/// 全局录制引用计数守卫：确保多个录制器切换或中途销毁时，全局热键开关始终成对安全恢复。
@MainActor
final class ShortcutRecordingGate {
    static let shared = ShortcutRecordingGate(setGlobalEnabled: { KeyboardShortcuts.isEnabled = $0 })

    private let setGlobalEnabled: (Bool) -> Void
    private(set) var activeCount = 0

    init(setGlobalEnabled: @escaping (Bool) -> Void) {
        self.setGlobalEnabled = setGlobalEnabled
    }

    func beginRecording() {
        activeCount += 1
        if activeCount == 1 {
            setGlobalEnabled(false)
        }
    }

    func endRecording() {
        guard activeCount > 0 else { return }
        activeCount -= 1
        if activeCount == 0 {
            setGlobalEnabled(true)
        }
    }
}
