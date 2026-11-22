import XCTest
import AppKit
import Carbon.HIToolbox
import KeyboardShortcuts
@testable import MeowOut

@MainActor
final class ShortcutRecorderTests: XCTestCase {

    func testModifierSymbolsFollowAppleHIGOrder() {
        let all: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
        XCTAssertEqual(ShortcutDisplayFormatter.modifierSymbols(from: all), ["⌃", "⌥", "⇧", "⌘"])
        XCTAssertEqual(ShortcutDisplayFormatter.modifierSymbols(from: [.command, .shift]), ["⇧", "⌘"])
        XCTAssertEqual(ShortcutDisplayFormatter.modifierSymbols(from: []), [])
    }

    func testShortcutDisplayFormattingAndSpaceRule() {
        let semicolon = KeyboardShortcuts.Shortcut(.semicolon, modifiers: [.command, .shift])
        XCTAssertEqual(ShortcutDisplayFormatter.format(shortcut: semicolon), "⇧ ⌘ ;")

        let space = KeyboardShortcuts.Shortcut(.space, modifiers: [.control, .option, .command])
        XCTAssertEqual(ShortcutDisplayFormatter.format(shortcut: space), "⌃ ⌥ ⌘ Space")

        let f5 = KeyboardShortcuts.Shortcut(.f5, modifiers: [])
        XCTAssertEqual(ShortcutDisplayFormatter.format(shortcut: f5), "F5")

        XCTAssertEqual(
            ShortcutDisplayFormatter.formatLiveModifiers([.command, .option]),
            "⌥ ⌘ …"
        )
    }

    func testInputValidatorClassifiesKeysCorrectly() {
        XCTAssertEqual(
            ShortcutInputValidator.classify(keyCode: UInt16(kVK_Escape), modifiers: [], isFunctionKey: false),
            .cancel
        )
        XCTAssertEqual(
            ShortcutInputValidator.classify(keyCode: UInt16(kVK_Delete), modifiers: [], isFunctionKey: false),
            .clear
        )
        XCTAssertEqual(
            ShortcutInputValidator.classify(keyCode: UInt16(kVK_ForwardDelete), modifiers: [], isFunctionKey: false),
            .clear
        )
        XCTAssertEqual(
            ShortcutInputValidator.classify(keyCode: UInt16(kVK_Tab), modifiers: [], isFunctionKey: false),
            .moveFocus
        )
        XCTAssertEqual(
            ShortcutInputValidator.classify(keyCode: UInt16(kVK_ANSI_A), modifiers: [], isFunctionKey: false),
            .requiresModifier
        )
        XCTAssertEqual(
            ShortcutInputValidator.classify(keyCode: UInt16(kVK_ANSI_A), modifiers: [.command], isFunctionKey: false),
            .recordable
        )
        XCTAssertEqual(
            ShortcutInputValidator.classify(keyCode: UInt16(kVK_F5), modifiers: [], isFunctionKey: true),
            .recordable
        )
        // Delete with modifier is a real shortcut candidate, not clear
        XCTAssertEqual(
            ShortcutInputValidator.classify(keyCode: UInt16(kVK_Delete), modifiers: [.command], isFunctionKey: false),
            .recordable
        )
    }

    func testAppShortcutRegistryCoversAllSevenShortcutsAndDetectsConflicts() {
        let registeredNames = Set(AppShortcutRegistry.allEntries.map(\.name))
        XCTAssertEqual(registeredNames.count, 7)
        XCTAssertTrue(registeredNames.contains(.togglePanel))
        XCTAssertTrue(registeredNames.contains(.toggleClipboardHistoryPanel))
        XCTAssertTrue(registeredNames.contains(.toggleShelf))
        XCTAssertTrue(registeredNames.contains(.toggleLauncher))
        XCTAssertTrue(registeredNames.contains(.toggleFundPanel))
        XCTAssertTrue(registeredNames.contains(.toggleMemosQuickCapture))
        XCTAssertTrue(registeredNames.contains(.toggleMemosBrowserWindow))

        let cmdShiftC = KeyboardShortcuts.Shortcut(.c, modifiers: [.command, .shift])
        let cmdShiftL = KeyboardShortcuts.Shortcut(.l, modifiers: [.command, .shift])
        let mockLookup: (KeyboardShortcuts.Name) -> KeyboardShortcuts.Shortcut? = { name in
            switch name {
            case .toggleClipboardHistoryPanel: return cmdShiftC
            case .toggleLauncher: return cmdShiftL
            default: return nil
            }
        }

        // Conflict with another shortcut
        let conflict = AppShortcutRegistry.conflictingEntry(
            for: cmdShiftC,
            excluding: .togglePanel,
            lookup: mockLookup
        )
        XCTAssertEqual(conflict?.name, .toggleClipboardHistoryPanel)

        // Re-recording the same shortcut on itself is NOT a conflict
        let selfCheck = AppShortcutRegistry.conflictingEntry(
            for: cmdShiftC,
            excluding: .toggleClipboardHistoryPanel,
            lookup: mockLookup
        )
        XCTAssertNil(selfCheck)
    }

    func testRecordingGateReferenceCountsGlobalHotkeys() {
        var enabledTransitions: [Bool] = []
        let gate = ShortcutRecordingGate(setGlobalEnabled: { enabledTransitions.append($0) })

        XCTAssertEqual(gate.activeCount, 0)
        gate.beginRecording()
        XCTAssertEqual(gate.activeCount, 1)
        XCTAssertEqual(enabledTransitions, [false])

        // Nested recorder starting should not re-emit
        gate.beginRecording()
        XCTAssertEqual(gate.activeCount, 2)
        XCTAssertEqual(enabledTransitions, [false])

        // Ending first leaves global hotkeys disabled
        gate.endRecording()
        XCTAssertEqual(gate.activeCount, 1)
        XCTAssertEqual(enabledTransitions, [false])

        // Ending last re-enables global hotkeys
        gate.endRecording()
        XCTAssertEqual(gate.activeCount, 0)
        XCTAssertEqual(enabledTransitions, [false, true])

        // Extra endRecording is safely clamped
        gate.endRecording()
        XCTAssertEqual(gate.activeCount, 0)
        XCTAssertEqual(enabledTransitions, [false, true])
    }

    func testShortcutRecorderLocalizationKeysExistInZhAndEn() {
        let keys = [
            "shortcut_record_placeholder",
            "shortcut_press_prompt",
            "shortcut_clear_tooltip",
            "shortcut_reset_default",
            "shortcut_modifier_required",
            "shortcut_conflict_in_app",
            "shortcut_conflict_main_menu",
            "shortcut_disallowed_sandbox",
        ]

        for key in keys {
            let zh = I18n.localized(key, language: .zhHans)
            let en = I18n.localized(key, language: .en)
            XCTAssertNotEqual(zh, key, "Missing zh-Hans localization for \(key)")
            XCTAssertNotEqual(en, key, "Missing en localization for \(key)")
            XCTAssertFalse(zh.isEmpty)
            XCTAssertFalse(en.isEmpty)
        }
    }

    func testShortcutRecorderArchitectureConstraints() throws {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let relativePath = "Sources/MeowOut/Settings/ShortcutRecorderView.swift"
        var sourceURL = directory.appendingPathComponent(relativePath)

        while !FileManager.default.fileExists(atPath: sourceURL.path) {
            let parent = directory.deletingLastPathComponent()
            if parent.path == directory.path {
                XCTFail("Could not locate \(relativePath)")
                return
            }
            directory = parent
            sourceURL = directory.appendingPathComponent(relativePath)
        }

        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        XCTAssertTrue(source.contains("class ShortcutRecorderControl: NSControl"))
        XCTAssertFalse(source.contains("NSSearchField"))
        XCTAssertFalse(source.contains("NSSearchFieldCell"))
        XCTAssertFalse(source.contains("searchButtonCell"))
        XCTAssertFalse(source.contains("cancelButtonCell"))
        XCTAssertTrue(source.contains("override var inputContext: NSTextInputContext? { nil }"))
        XCTAssertTrue(source.contains("NSEvent.addLocalMonitorForEvents"))
        XCTAssertTrue(source.contains("NSEvent.removeMonitor"))
        XCTAssertTrue(source.contains("flagsChanged"))
    }
}
