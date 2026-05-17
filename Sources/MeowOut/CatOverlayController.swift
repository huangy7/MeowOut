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

    private let petState = PetState()
    private var timer: Timer?

    private let petWindowSize = NSSize(width: 60, height: 60)
    private let bubbleWindowSize = NSSize(width: 200, height: 60)
    private var patrolVelocity: CGPoint = CGPoint(x: 3.0, y: 1.5)
    // For dialogue shuffling
    private var lastDialogueUpdate: Date = Date()
    private var currentDialogueIndex: Int = 0

    private var localMonitor: Any?
    private var mouseOffsetInWindow: CGSize = .zero

    private init() {}

    public func start(appState: AppState) {
        self.appState = appState
        self.escapeHatch = EscapeHatch(appState: appState)

        NotificationCenter.default.addObserver(forName: NSNotification.Name("TriggerEscapeHatch"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.escapeHatch?.triggerEscape() }
        }

        withObservationTracking {
            _ = appState.currentState
        } onChange: {
            Task { @MainActor in self.evaluateState() }
        }

        setupInputMonitoring()
        evaluateState()
    }

    private func evaluateState() {
        guard let state = appState else { return }

        if state.currentState == .resting {
            escapeHatch?.startMonitoring()
        } else {
            escapeHatch?.stopMonitoring()
        }

        if state.currentState == .alerting || state.currentState == .resting {
            showWindows()
            startTimer()
        } else {
            hideWindows()
            stopTimer()
        }

        withObservationTracking {
            _ = self.appState?.currentState
        } onChange: {
            Task { @MainActor [weak self] in self?.evaluateState() }
        }
    }

    private func setupInputMonitoring() {
        if localMonitor != nil { return }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { [weak self] event in
            guard let self = self, let state = self.appState,
                  (state.currentState == .resting || state.currentState == .alerting) else { return event }

            let pack = DialogueManager.pack(for: state.selectedPersonality, language: state.language)

            if event.type == .keyDown {
                self.petState.showLockedBubble(pack.keyboardScold, duration: 2.0)
            } else if event.type == .leftMouseDown {
                // Precision Tray/Local check: If not on the pet window, it must be the tray
                if self.petWindow?.frame.contains(NSEvent.mouseLocation) == false {
                    self.petState.showLockedBubble(pack.trayScold, duration: 2.0)
                }
            }
            return event
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
            panel.contentView = NSHostingView(rootView: view)
            self.petWindow = panel
        }
        if bubbleWindow == nil {
            let panel = createPanel(size: bubbleWindowSize, ignoresMouse: true)
            let view = MeowBubbleView(petState: petState)
            panel.contentView = NSHostingView(rootView: view)
            self.bubbleWindow = panel
        }
        petWindow?.orderFront(nil)
        bubbleWindow?.orderFront(nil)
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
        updateDialogue(state: state)
    }

    private func updateDialogue(state: AppState) {
        if petState.isBubbleLocked { return }
        let now = Date()
        guard now.timeIntervalSince(lastDialogueUpdate) > 4.0 else { return }

        let pack = DialogueManager.pack(for: state.selectedPersonality, language: state.language)
        let dialogues: [String]
        if state.currentState == .alerting {
            dialogues = pack.alerting
        } else if state.currentState == .resting {
            dialogues = pack.resting
        } else {
            petState.bubbleVisible = false
            return
        }

        currentDialogueIndex = (currentDialogueIndex + 1) % dialogues.count
        petState.bubbleText = dialogues[currentDialogueIndex]
        petState.bubbleVisible = true
        lastDialogueUpdate = now
    }

    private func updateWindowPositions() {
        guard let pw = petWindow, let bw = bubbleWindow else { return }
        pw.setFrameOrigin(NSPoint(x: petState.position.x - petWindowSize.width / 2, y: petState.position.y - petWindowSize.height / 2))
        bw.setFrameOrigin(NSPoint(x: petState.position.x - bubbleWindowSize.width / 2, y: petState.position.y + petWindowSize.height / 2 + 5))
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
