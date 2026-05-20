import AppKit

@MainActor
public final class WaterReminderController {
    private weak var appState: AppState?
    private let petState: PetState

    private var lastWaterReminderCheck: Date = Date()
    private var waterBubbleDismissTask: Task<Void, Never>?

    public init(appState: AppState, petState: PetState) {
        self.appState = appState
        self.petState = petState
    }

    /// Reset the custom-mode timer — called when windows appear to give a fresh interval
    public func resetTimer() {
        lastWaterReminderCheck = Date()
    }

    /// Called every tick — checks custom-mode timer and shows bubble if due
    public func tick() {
        guard let state = appState else { return }
        guard state.waterReminderEnabled else { return }
        guard state.currentState != .resting else { return }
        guard state.currentState == .working || state.currentState == .alerting else { return }
        guard !petState.isBubbleLocked else { return }
        guard !petState.showWaterButton else { return }

        if state.waterReminderMode == .custom {
            let interval = TimeInterval(state.waterCustomInterval * 60)
            let now = Date()
            if now.timeIntervalSince(lastWaterReminderCheck) >= interval {
                lastWaterReminderCheck = now
                showBubble()
            }
        }
    }

    /// Show water reminder bubble (followRhythm mode calls this directly from updateDialogue)
    public func showBubble() {
        guard let state = appState else { return }
        petState.bubbleText = I18n.localized("water_reminder_text", language: state.language)
        petState.showWaterButton = true
        petState.bubbleVisible = true

        waterBubbleDismissTask?.cancel()
        waterBubbleDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard let self, !Task.isCancelled else { return }
            self.petState.bubbleVisible = false
            self.petState.showWaterButton = false
        }
    }

    /// Called when user clicks +1 on water bubble
    public func handleWaterAdded() {
        guard let state = appState else { return }
        state.todayWaterCups += 1
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        petState.showWaterButton = false
        petState.bubbleText = I18n.localized("water_recorded", language: state.language)
        waterBubbleDismissTask?.cancel()
        waterBubbleDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let self, !Task.isCancelled else { return }
            self.petState.bubbleVisible = false
        }
    }
}
