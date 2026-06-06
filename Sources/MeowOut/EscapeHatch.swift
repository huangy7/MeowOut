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
        guard appState.currentState == .resting || appState.currentState == .overworking else { return }
        let now = Date()
        // Keep presses within the last 2 seconds
        escPresses = escPresses.filter { now.timeIntervalSince($0) < 2.0 }
        escPresses.append(now)

        if escPresses.count >= 5 {
            triggerEscape()
        }
    }

    public func triggerEscape() {
        if appState.currentState == .alerting {
            appState.warningDismissed = true
        }
        // Only reset work timer when escaping from forced rest, not from alerting warning
        if appState.currentState == .resting || appState.currentState == .overworking {
            appState.workElapsed = 0
            appState.todayEscapeCount += 1
        }
        appState.currentState = .working
        escPresses.removeAll()
    }

    /// Process one frame of the escape run-off-screen animation.
    /// Returns true if the escape animation is still in progress (caller should skip normal tick logic).
    public func tick(petState: PetState, screen: NSRect) -> Bool {
        guard petState.isEscaping else { return false }

        petState.isWalking = true
        petState.facingRight = true
        petState.position.x += 4.5

        // Hide bubble as we run away past center
        if petState.position.x > screen.midX + 100 {
            petState.bubbleVisible = false
        }

        if petState.position.x > screen.maxX + 100 {
            // Fully off-screen, finalize escape
            petState.isEscaping = false
            petState.isWalking = false
            return false
        }

        return true
    }
}
