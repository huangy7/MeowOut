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
    private let bubbleWindowSize = NSSize(width: 220, height: 60)
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

        withObservationTracking {
            _ = appState.currentState
        } onChange: {
            Task { @MainActor in self.evaluateState() }
        }

        setupInputMonitoring()
        evaluateState()
    }

    public func triggerTrayScold() {
        guard let state = appState else { return }
        if state.currentState == .resting || state.currentState == .alerting {
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

        if state.currentState == .resting {
            escapeHatch?.startMonitoring()
        } else {
            escapeHatch?.stopMonitoring()
        }

        if state.currentState == .alerting || state.currentState == .resting || state.currentState == .breathing {
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

        // Local monitor (always on during alerting/resting)
        if state.currentState == .alerting || state.currentState == .resting {
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
        if state.enableGlobalKeyboardScold && (state.currentState == .alerting || state.currentState == .resting) && AXIsProcessTrusted() {
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
        guard let state = appState, (state.currentState == .resting || state.currentState == .alerting) else { return }
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
            let panel = createPanel(size: bubbleWindowSize, ignoresMouse: false)
            let view = MeowBubbleView(petState: petState, onWaterAdd: { [weak self] in
                self?.waterReminderController?.handleWaterAdded()
            })
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
        if state.currentState == .resting {
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

            let topSafeArea: CGFloat = 100.0
            let minYBoundary = screen.maxY - topSafeArea
            let maxYBoundary = screen.maxY - 30

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
        let now = Date()
        guard now.timeIntervalSince(lastDialogueUpdate) > 4.0 else { return }

        let pack = DialogueManager.pack(for: state.selectedPersonality, language: state.language)
        let dialogues: [String]
        if state.currentState == .alerting {
            dialogues = pack.alerting
            petState.showBreathingButton = false
        } else if state.currentState == .resting {
            dialogues = pack.resting
            petState.showBreathingButton = true
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
        bw.setFrameOrigin(NSPoint(x: petState.position.x - bubbleWindowSize.width / 2, y: petState.position.y + petWindowSize.height / 2 + 5))
        
        // Ensure bubble window doesn't block clicks when invisible
        bw.ignoresMouseEvents = !petState.bubbleVisible
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
}
