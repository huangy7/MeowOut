import AppKit
import ApplicationServices
import SwiftUI

@MainActor
final class KeyboardCleaningService {
    static let shared = KeyboardCleaningService()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var overlayWindows: [NSWindow] = []

    private(set) var isEnabled = false

    private init() {}

    func start(language: AppState.AppLanguage = .system, onExit: @escaping () -> Void) throws {
        guard !isEnabled else { return }

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else {
            throw NSError(domain: "KeyboardCleaningService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Keyboard Cleaning requires Accessibility permission."])
        }

        try startEventTap()
        showOverlay(language: language, onExit: onExit)
        isEnabled = true
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        overlayWindows.forEach { $0.close() }
        overlayWindows.removeAll()
        isEnabled = false
    }

    private func startEventTap() throws {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) |
            CGEventMask(1 << CGEventType.keyUp.rawValue) |
            CGEventMask(1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, _ in
                switch type {
                case .keyDown, .keyUp, .flagsChanged:
                    return nil
                default:
                    return Unmanaged.passUnretained(event)
                }
            },
            userInfo: nil
        ) else {
            throw NSError(domain: "KeyboardCleaningService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Unable to start keyboard event interception."])
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func showOverlay(language: AppState.AppLanguage, onExit: @escaping () -> Void) {
        let screens = NSScreen.screens.isEmpty ? [NSScreen.main].compactMap { $0 } : NSScreen.screens
        overlayWindows = screens.map { screen in
            let view = KeyboardCleaningOverlayView(language: language) { [weak self] in
                self?.stop()
                onExit()
            }

            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.contentView = NSHostingView(rootView: view)
            window.isReleasedWhenClosed = false
            window.level = .screenSaver
            window.backgroundColor = NSColor.windowBackgroundColor
            return window
        }

        NSApp.activate(ignoringOtherApps: true)
        overlayWindows.first?.makeKeyAndOrderFront(nil)
        overlayWindows.dropFirst().forEach { $0.orderFrontRegardless() }
    }
}
