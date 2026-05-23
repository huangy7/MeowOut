import AppKit
import SwiftUI
import Observation

@MainActor
public final class CatOverlayController {
    public static let shared = CatOverlayController()

    private var petWindow: NSPanel?
    private var bubbleWindow: NSPanel?
    private var appState: AppState?
    private var escapeHatch: EscapeHatch?
    private var waterReminderController: WaterReminderController?

    private let petState = PetState()
    private var timer: Timer?

    private let petWindowSize = NSSize(width: 60, height: 60)
    private let defaultBubbleWindowSize = NSSize(width: 260, height: 115)
    private let maxBubbleWindowWidth: CGFloat = 260
    private let bubbleGap: CGFloat = -6 // Since the cat sprite is centered vertically in petWindowSize (height 40 vs 60), there is 10pt of empty space at the top. A bubbleGap of -6 yields a 4pt visual gap.
    private var currentBubbleWindowSize = NSSize(width: 260, height: 115)

    nonisolated static func bubbleFrame(
        petCenter: CGPoint,
        petSize: CGSize,
        bubbleSize: CGSize,
        gap: CGFloat
    ) -> CGRect {
        let petTop = petCenter.y + petSize.height / 2
        let bubbleBottom = petTop + gap
        return CGRect(
            x: petCenter.x - bubbleSize.width / 2,
            y: bubbleBottom,
            width: bubbleSize.width,
            height: bubbleSize.height
        )
    }

    private var patrolVelocity: CGPoint = CGPoint(x: 3.0, y: 1.5)
    // For dialogue shuffling
    private var lastDialogueUpdate: Date = Date()
    private var currentDialogueIndex: Int = 0
    private var showHintNext: Bool = false

    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var mouseOffsetInWindow: CGSize = .zero
    
    private var originalStateForPreview: AppPhase? = nil

    private init() {}

    public func start(appState: AppState) {
        self.appState = appState
        self.escapeHatch = EscapeHatch(appState: appState)
        self.waterReminderController = WaterReminderController(appState: appState, petState: petState)

        NotificationCenter.default.addObserver(forName: NSNotification.Name("TriggerEscapeHatch"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.petState.isEscaping = true
            }
        }

        NotificationCenter.default.addObserver(forName: .keyDropRequireAccessibility, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.handleKeyDropRequireAccessibility()
            }
        }

        withObservationTracking {
            _ = appState.currentState
            _ = petState.updateInteraction
            _ = petState.isBubbleLocked
        } onChange: {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.evaluateState()
            }
        }

        setupInputMonitoring()
        startUpdateObservation()
        evaluateState()
        handleUpdateStatusChanged()
    }

    private func startUpdateObservation() {
        withObservationTracking {
            _ = UpdateChecker.shared.status
        } onChange: {
            Task { @MainActor [weak self] in
                self?.handleUpdateStatusChanged()
                self?.startUpdateObservation()
            }
        }
    }

    private func handleUpdateStatusChanged() {
        guard let state = appState else { return }
        guard case let .available(version, _, _) = UpdateChecker.shared.status else { return }
        guard state.lastNotifiedUpdateVersion != version else { return }

        state.lastNotifiedUpdateVersion = version
        showWindows()
        startTimer()
        let text = I18n.localizedFormat("update_pet_prompt", language: state.language, version)
        petState.showUpdateBubble(text: text, version: version)
        updateWindowPositions()
    }

    public func triggerTrayScold() {
        guard let state = appState else { return }
        if state.currentState == .resting || state.currentState == .overworking || state.currentState == .alerting {
            let pack = DialogueManager.pack(for: state.selectedPersonality, language: state.language)
            self.petState.showLockedBubble(pack.trayScold, duration: 2.0)
        }
    }

    public func previewAlerting() {
        guard let state = appState else { return }
        if state.isPreviewing {
            stopPreview()
            return
        }

        let originalState = state.currentState
        guard originalState != .alerting && originalState != .resting else { return }

        originalStateForPreview = originalState
        resetPetPositionForPreview()
        state.isPreviewing = true
        state.restRemaining = state.defaultRestTime
        state.currentState = .alerting
    }

    public func previewResting() {
        guard let state = appState else { return }
        if state.isPreviewing {
            stopPreview()
            return
        }

        let originalState = state.currentState
        guard originalState != .alerting && originalState != .resting else { return }

        originalStateForPreview = originalState
        resetPetPositionForPreview()
        state.isPreviewing = true
        state.restRemaining = state.defaultRestTime
        state.currentState = .resting
    }

    private func resetPetPositionForPreview() {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        petState.position = CGPoint(x: screen.midX, y: screen.midY)
    }
    
    public func stopPreview() {
        guard let state = appState else { return }
        guard state.isPreviewing else { return }
        
        state.isPreviewing = false
        if let orig = originalStateForPreview {
            state.currentState = orig
            originalStateForPreview = nil
        }
        
        // Reset pet state to prevent it from continuing an escape animation next time
        petState.isEscaping = false
        petState.isWalking = false
        petState.tapCount = 0
    }

    private func evaluateState() {
        guard let state = appState else { return }

        if state.currentState == .resting || state.currentState == .overworking {
            escapeHatch?.startMonitoring()
            petState.showBreathingButton = true
        } else {
            escapeHatch?.stopMonitoring()
            petState.showBreathingButton = false
        }

        if state.currentState == .alerting || state.currentState == .resting || state.currentState == .overworking || state.currentState == .breathing || petState.updateInteraction != nil || petState.isBubbleLocked {
            showWindows()
            startTimer()
        } else {
            hideWindows()
            stopTimer()
        }

        withObservationTracking {
            _ = self.appState?.currentState
            _ = self.appState?.enableGlobalKeyboardScold
            _ = self.appState?.isBreathingActive
            _ = self.petState.isBubbleLocked
        } onChange: {
            Task { @MainActor [weak self] in
                guard let self else { return }
                // When breathing becomes active, clear the bubble exactly once
                if self.appState?.isBreathingActive == true {
                    self.petState.bubbleVisible = false
                    self.petState.showBreathingButton = false
                }
                self.evaluateState()
            }
        }
        
        updateInputMonitors()
    }

    private func updateInputMonitors() {
        guard let state = appState else { return }

        // Local monitor (always on during alerting/resting/overworking)
        if state.currentState == .alerting || state.currentState == .resting || state.currentState == .overworking {
            if localMonitor == nil {
                localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
                    self?.handleKeyDown()
                    return event
                }
            }
        } else {
            if let lm = localMonitor {
                NSEvent.removeMonitor(lm)
                localMonitor = nil
            }
        }

        // Global monitor
        if state.enableGlobalKeyboardScold && (state.currentState == .alerting || state.currentState == .resting || state.currentState == .overworking) && AXIsProcessTrusted() {
            if globalMonitor == nil {
                globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] _ in
                    self?.handleKeyDown()
                }
            }
        } else {
            if let gm = globalMonitor {
                NSEvent.removeMonitor(gm)
                globalMonitor = nil
            }
        }
    }

    private func handleKeyDown() {
        guard let state = appState, (state.currentState == .resting || state.currentState == .overworking || state.currentState == .alerting) else { return }
        let pack = DialogueManager.pack(for: state.selectedPersonality, language: state.language)
        self.petState.showLockedBubble(pack.keyboardScold, duration: 2.0)
    }

    private func setupInputMonitoring() {
        NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.triggerTrayScold()
            }
        }
    }

    private func showWindows() {
        guard let state = appState else { return }
        if petWindow == nil {
            let mouseLocation = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main
            let screenFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
            let isOffscreen = petState.position.x < screenFrame.minX ||
                              petState.position.x > screenFrame.maxX ||
                              petState.position.y < screenFrame.minY ||
                              petState.position.y > screenFrame.maxY
            if isOffscreen {
                petState.position = CGPoint(x: screenFrame.midX, y: screenFrame.midY)
            }

            let panel = createPanel(size: petWindowSize, ignoresMouse: false)
            let view = MeowView(
                appState: state,
                petState: petState,
                onDragStarted: { [weak self] in self?.handleDragStarted() },
                onDragChanged: { [weak self] t in self?.handleDragChanged(translation: t) },
                onDragEnded: { [weak self] t in self?.handleDragEnded(translation: t) }
            )
            let hosting = NSHostingView(rootView: view)
            if #available(macOS 13.0, *) { hosting.sizingOptions = [] }
            panel.contentView = hosting
            self.petWindow = panel
        }
        if bubbleWindow == nil {
            currentBubbleWindowSize = defaultBubbleWindowSize
            let panel = createPanel(size: defaultBubbleWindowSize, ignoresMouse: false)
            let view = MeowBubbleView(
                petState: petState,
                appState: state,
                onWaterAdd: { [weak self] in
                    self?.waterReminderController?.handleWaterAdded()
                },
                onUpdateNow: { [weak self] in
                    self?.openUpdateSettings()
                },
                onUpdateLater: { [weak self] in
                    self?.hideUpdateWindowsIfIdle()
                },
                onSizeChange: { [weak self] size in
                    self?.updateBubbleWindowSize(size)
                }
            )
            let hosting = NSHostingView(rootView: view)
            if #available(macOS 13.0, *) { hosting.sizingOptions = [] }
            panel.contentView = hosting
            self.bubbleWindow = panel
        }
        petWindow?.orderFront(nil)
        bubbleWindow?.orderFront(nil)
        currentDialogueIndex = 0
        showHintNext = false
        lastDialogueUpdate = Date()
        waterReminderController?.resetTimer()
        updateWindowPositions()
    }

    private func openUpdateSettings() {
        appState?.settingsNavigationTarget = .update
        hideUpdateWindowsIfIdle()
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: NSNotification.Name("OpenSettingsWindow"), object: nil)
    }

    private func hideUpdateWindowsIfIdle() {
        guard let state = appState else { return }
        guard state.currentState != .alerting, state.currentState != .resting, state.currentState != .overworking, state.currentState != .breathing else { return }
        hideWindows()
        stopTimer()
    }

    private func createPanel(size: NSSize, ignoresMouse: Bool) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: petState.position, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = ignoresMouse
        return panel
    }

    private func hideWindows() {
        petWindow?.orderOut(nil)
        bubbleWindow?.orderOut(nil)
        petWindow = nil
        bubbleWindow = nil
        currentBubbleWindowSize = defaultBubbleWindowSize
    }

    private func startTimer() {
        timer?.invalidate()
        // 🔥 性能平衡：同步提升至 30 FPS (0.033s)
        timer = Timer.scheduledTimer(withTimeInterval: 0.033, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        if petState.isBeingDragged { return }
        guard let state = appState else { return }
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)

        // --- 0. Escape Animation: delegate to EscapeHatch ---
        if petState.isEscaping {
            let stillRunning = escapeHatch?.tick(petState: petState, screen: screen) ?? false
            updateWindowPositions()
            if !stillRunning {
                if state.isPreviewing {
                    stopPreview()
                } else {
                    escapeHatch?.triggerEscape()
                }
            }
            return
        }

        // --- Breathing Anchor: keep cat at bottom-center of breathing window ---
        if state.isBreathingActive {
            if let breathingWindow = NSApp.windows.first(where: { $0.title == "正念练习" && $0.isVisible }),
               let petWindow = self.petWindow,
               let bubbleWindow = self.bubbleWindow {
                
                // Ensure pet is ordered above the breathing window if they share the same level
                petWindow.order(.above, relativeTo: breathingWindow.windowNumber)
                bubbleWindow.order(.above, relativeTo: petWindow.windowNumber)
                
                let wf = breathingWindow.frame
                let targetX = wf.midX
                let targetY = wf.minY - petWindowSize.height / 2 - 4
                // Smoothly glide toward target
                let dx = targetX - petState.position.x
                let dy = targetY - petState.position.y
                let dist = sqrt(dx * dx + dy * dy)
                if dist > 2 {
                    let speed: CGFloat = min(dist, 6.0)
                    petState.position.x += (dx / dist) * speed
                    petState.position.y += (dy / dist) * speed
                    petState.isWalking = true
                    petState.facingRight = dx > 0
                } else {
                    petState.position = CGPoint(x: targetX, y: targetY)
                    petState.isWalking = false
                }
                updateWindowPositions()
                return
            }
        }
        
        // --- 1. Movement Logic ---
        if state.currentState == .resting || state.currentState == .overworking {
            if state.enableCursorChasing {
                let mouseLocation = NSEvent.mouseLocation
                let dx = mouseLocation.x - petState.position.x
                let dy = mouseLocation.y - petState.position.y
                let dist = sqrt(dx*dx + dy*dy)
                let targetDist: CGFloat = 120.0

                if dist > targetDist + 10 {
                    petState.isWalking = true
                    let speed: CGFloat = 2.5
                    let vx = (dx / dist) * speed
                    let vy = (dy / dist) * speed
                    petState.position.x += vx
                    petState.position.y += vy
                    petState.facingRight = vx > 0
                } else {
                    petState.isWalking = false
                    petState.facingRight = dx > 0
                }
            } else {
                // RESTING (Chasing Disabled): Aggressive Full-screen Patrol
                petState.isWalking = true
                let aggressiveSpeed: CGFloat = 5.0
                let currentSpeed = sqrt(patrolVelocity.x * patrolVelocity.x + patrolVelocity.y * patrolVelocity.y)
                if currentSpeed > 0 {
                    patrolVelocity.x = (patrolVelocity.x / currentSpeed) * aggressiveSpeed
                    patrolVelocity.y = (patrolVelocity.y / currentSpeed) * aggressiveSpeed
                }
                petState.position.x += patrolVelocity.x
                petState.position.y += patrolVelocity.y
                petState.facingRight = patrolVelocity.x > 0
                if Int.random(in: 0..<50) == 0 { patrolVelocity.y = CGFloat.random(in: -4.0...4.0) }
                if petState.position.x <= screen.minX + 30 { petState.position.x = screen.minX + 30; patrolVelocity.x = abs(patrolVelocity.x) }
                else if petState.position.x >= screen.maxX - 30 { petState.position.x = screen.maxX - 30; patrolVelocity.x = -abs(patrolVelocity.x) }
                if petState.position.y <= screen.minY + 30 { petState.position.y = screen.minY + 30; patrolVelocity.y = abs(patrolVelocity.y) }
                else if petState.position.y >= screen.maxY - 30 { petState.position.y = screen.maxY - 30; patrolVelocity.y = -abs(patrolVelocity.y) }
            }
        } else if state.currentState == .alerting {
            // ALERTING: Naturally walk to top-of-screen
            petState.isWalking = true
            let mildSpeed: CGFloat = 1.5

            // Adjust boundaries to ensure the pet doesn't go off-screen or too high
            // Visible frame usually excludes menu bar, but we want a safe margin from the top
            let topMargin: CGFloat = 60.0
            let minYBoundary = screen.maxY - 120.0
            let maxYBoundary = screen.maxY - topMargin

            // 1. Vertical Movement: If not in the top area, move UP
            if petState.position.y < minYBoundary {
                petState.position.y += mildSpeed // Climb up
            } else if petState.position.y > maxYBoundary {
                petState.position.y -= mildSpeed // Drift down slightly if too high
            }

            // 2. Horizontal Movement: Always move sideways
            petState.position.x += patrolVelocity.x > 0 ? mildSpeed : -mildSpeed

            // Bounce horizontally
            if petState.position.x <= screen.minX + 30 {
                petState.position.x = screen.minX + 30
                patrolVelocity.x = abs(patrolVelocity.x)
            } else if petState.position.x >= screen.maxX - 30 {
                petState.position.x = screen.maxX - 30
                patrolVelocity.x = -abs(patrolVelocity.x)
            }

            petState.facingRight = patrolVelocity.x > 0
        }

        updateWindowPositions()
        waterReminderController?.tick()
        updateDialogue(state: state)
    }

    private func updateDialogue(state: AppState) {
        // Don't update dialogue at all during breathing — bubble is cleared reactively
        guard !state.isBreathingActive else { return }
        if petState.isBubbleLocked { return }
        
        // If an update is pending, keep showing the update prompt
        if let interaction = petState.updateInteraction {
            let text = I18n.localizedFormat("update_pet_prompt", language: state.language, interaction.version)
            if petState.bubbleText != text {
                petState.bubbleText = text
                petState.bubbleVisible = true
            }
            return
        }

        let now = Date()
        guard now.timeIntervalSince(lastDialogueUpdate) > 4.0 else { return }

        let pack = DialogueManager.pack(for: state.selectedPersonality, language: state.language)
        let dialogues: [String]
        if state.currentState == .alerting {
            dialogues = pack.alerting
        } else if state.currentState == .resting || state.currentState == .overworking {
            dialogues = pack.resting
        } else {
            petState.bubbleVisible = false
            return
        }

        // Insert tap hint after each full dialogue cycle
        if showHintNext {
            let targetCount = (state.currentState == .alerting) ? 3 : 5
            petState.bubbleText = DialogueManager.tapHintText(
                personality: state.selectedPersonality,
                language: state.language,
                targetCount: targetCount
            )
            petState.bubbleVisible = true
            lastDialogueUpdate = now
            showHintNext = false
            return
        }

        // followRhythm 模式：预警阶段每隔一条对话插入喝水提醒
        if state.waterReminderEnabled && state.waterReminderMode == .followRhythm && state.currentState == .alerting {
            if currentDialogueIndex % 2 == 1 {
                waterReminderController?.showBubble()
                lastDialogueUpdate = now
                currentDialogueIndex = (currentDialogueIndex + 1) % dialogues.count
                return
            }
        }

        petState.bubbleText = dialogues[currentDialogueIndex]
        petState.bubbleVisible = true
        lastDialogueUpdate = now
        currentDialogueIndex += 1
        if currentDialogueIndex >= dialogues.count {
            currentDialogueIndex = 0
            showHintNext = true
        }
    }

    private func updateWindowPositions() {
        guard let pw = petWindow, let bw = bubbleWindow else { return }
        pw.setFrameOrigin(NSPoint(x: petState.position.x - petWindowSize.width / 2, y: petState.position.y - petWindowSize.height / 2))
        let bubbleFrame = Self.bubbleFrame(
            petCenter: petState.position,
            petSize: petWindowSize,
            bubbleSize: currentBubbleWindowSize,
            gap: bubbleGap
        )
        bw.setFrame(bubbleFrame, display: true)
        
        // Ensure bubble window doesn't block clicks when invisible
        bw.ignoresMouseEvents = !petState.bubbleVisible
    }

    private func updateBubbleWindowSize(_ measuredSize: CGSize) {
        guard measuredSize.width > 0, measuredSize.height > 0 else { return }

        let clampedSize = NSSize(
            width: maxBubbleWindowWidth,
            height: ceil(measuredSize.height)
        )
        guard currentBubbleWindowSize != clampedSize else { return }

        currentBubbleWindowSize = clampedSize
        updateWindowPositions()
    }

    // MARK: - Drag Handlers
    private func handleDragStarted() {
        guard let win = petWindow else { return }
        let mouseLoc = NSEvent.mouseLocation
        let winOrigin = win.frame.origin

        // Correctly assign mouseOffsetInWindow to prevent the pet from jumping
        mouseOffsetInWindow = CGSize(width: mouseLoc.x - winOrigin.x, height: mouseLoc.y - winOrigin.y)

        petState.isBeingDragged = true
        petState.isWalking = false
        petState.pose = .armsUp
        petState.bubbleVisible = false
    }

    private func handleDragChanged(translation: CGSize) {
        guard petState.isBeingDragged, let win = petWindow else { return }
        let mouseLoc = NSEvent.mouseLocation
        win.setFrameOrigin(NSPoint(x: mouseLoc.x - mouseOffsetInWindow.width, y: mouseLoc.y - mouseOffsetInWindow.height))
        let frame = win.frame
        petState.position = CGPoint(x: frame.midX, y: frame.midY)
        if abs(translation.width) > 8 { petState.facingRight = translation.width > 0 }
        updateWindowPositions()
    }

    private func handleDragEnded(translation: CGSize) {
        petState.isBeingDragged = false
        petState.pose = .rest
        lastDialogueUpdate = Date()
    }


    
    private func handleKeyDropRequireAccessibility() {
        guard let state = appState else { return }
        showWindows()
        startTimer()
        petState.pose = .armsUp
        let text = I18n.localized("dialogue_keydrop_require_accessibility", language: state.language)
        petState.showLockedBubble(text, duration: 5.0)
        
        NotificationCenter.default.post(name: NSNotification.Name("OpenSettingsWindow"), object: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(name: NSNotification.Name("SwitchToPermissionsTab"), object: nil)
        }
    }
}
