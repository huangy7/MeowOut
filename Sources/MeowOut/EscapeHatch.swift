// Sources/MeowOut/EscapeHatch.swift
import AppKit

@MainActor
public final class EscapeHatch {
    private let appState: AppState
    private var escPresses: [Date] = []
    private var eventMonitor: Any?

    public init(appState: AppState) {
        self.appState = appState
    }

    public func startMonitoring() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // ESC key
                self?.handleEscPress()
            }
            return event
        }
    }

    public func stopMonitoring() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    private func handleEscPress() {
        guard appState.currentState == .resting else { return }
        let now = Date()
        // Keep presses within the last 2 seconds
        escPresses = escPresses.filter { now.timeIntervalSince($0) < 2.0 }
        escPresses.append(now)

        if escPresses.count >= 5 {
            triggerEscape()
        }
    }

    public func triggerEscape() {
        appState.workElapsed = 0
        appState.currentState = .working
        escPresses.removeAll()
    }
}
