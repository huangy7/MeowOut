import SwiftUI

enum BreathingVisualMetrics {
    static let windowWidth: CGFloat = 320
    static let windowHeight: CGFloat = 420
    static let glowSize: CGFloat = 260
    static let animationFrameSize: CGFloat = 240
    static let breathingCircleSize: CGFloat = 164
    static let horizontalPadding: CGFloat = 22
    static let topPadding: CGFloat = 22
    static let bottomPadding: CGFloat = 28
}

public struct BreathingView: View {
    @State private var state = BreathingState()
    @State private var controlsVisible: Bool = true
    @State private var controlsTimer: Timer? = nil
    @Environment(AppState.self) private var appState

    public init() {}

    // MARK: - Computed properties

    private var circleScale: CGFloat {
        if !state.isRunning { return 0.7 }
        switch state.currentPhase {
        case .inhale, .holdAfterInhale: return 1.0
        case .exhale, .holdAfterExhale: return 0.7
        }
    }

    private var outerRingScale: CGFloat { circleScale * 1.25 }
    private var outerRingOpacity: Double { state.isRunning ? 0.25 : 0.0 }

    private var animationDuration: Double {
        switch state.currentPhase {
        case .inhale: return Double(state.currentPattern.inhaleDuration)
        case .exhale: return Double(state.currentPattern.exhaleDuration)
        case .holdAfterInhale, .holdAfterExhale: return 0
        }
    }

    private var phaseLabel: String {
        if !state.isRunning { return "准备好了" }
        return state.currentPhase.displayName
    }

    private var phaseSubLabel: String {
        if !state.isRunning { return "选择模式，点击开始" }
        return "\(state.secondsRemaining) 秒"
    }

    private var bgGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.05, green: 0.05, blue: 0.12),
                Color(red: 0.08, green: 0.10, blue: 0.20)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Body

    public var body: some View {
        ZStack {
            // Background
            bgGradient
                .ignoresSafeArea()

            // Ambient glow behind the circle
            Circle()
                .fill(Color.orange.opacity(0.07))
                .frame(width: BreathingVisualMetrics.glowSize, height: BreathingVisualMetrics.glowSize)
                .scaleEffect(circleScale * 1.5)
                .animation(
                    state.isRunning ? .easeInOut(duration: animationDuration) : .default,
                    value: circleScale
                )
                .blur(radius: 40)

            VStack(spacing: 0) {

                // ── Top controls (pattern picker + close) ──────────────────
                HStack {
                    // Custom chip-style pattern selector
                    HStack(spacing: 6) {
                        ForEach(BreathingPattern.all) { pattern in
                            Button {
                                state.setPattern(pattern)
                            } label: {
                                Text(shortName(pattern))
                                    .font(.system(size: 11, weight: state.currentPattern.id == pattern.id ? .semibold : .regular))
                                    .foregroundStyle(state.currentPattern.id == pattern.id ? Color.black : Color.white.opacity(0.55))
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule()
                                            .fill(state.currentPattern.id == pattern.id ? Color.orange : Color.white.opacity(0.10))
                                    )
                            }
                            .buttonStyle(.plain)
                            .disabled(state.isRunning)
                        }
                    }

                    Spacer()

                    Button {
                        state.stop()
                        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "breathing" }) {
                            window.close()
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.4))
                            .padding(8)
                            .background(Circle().fill(.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, BreathingVisualMetrics.horizontalPadding)
                .padding(.top, BreathingVisualMetrics.topPadding)
                .opacity(controlsVisible ? 1 : 0)
                .animation(.easeInOut(duration: 0.4), value: controlsVisible)

                Spacer()

                // ── Main animation ─────────────────────────────────────────
                ZStack {
                    // Outer ring pulse
                    Circle()
                        .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                        .frame(width: BreathingVisualMetrics.breathingCircleSize, height: BreathingVisualMetrics.breathingCircleSize)
                        .scaleEffect(outerRingScale)
                        .opacity(outerRingOpacity)
                        .animation(
                            state.isRunning ? .easeInOut(duration: animationDuration) : .default,
                            value: outerRingScale
                        )
                        .animation(
                            state.isRunning ? .easeInOut(duration: animationDuration) : .default,
                            value: outerRingOpacity
                        )

                    // Middle ring
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [Color.orange.opacity(0.8), Color.orange.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                        .frame(width: BreathingVisualMetrics.breathingCircleSize, height: BreathingVisualMetrics.breathingCircleSize)
                        .scaleEffect(circleScale)
                        .animation(
                            state.isRunning ? .easeInOut(duration: animationDuration) : .default,
                            value: circleScale
                        )

                    // Inner filled circle
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.orange.opacity(0.35), Color.orange.opacity(0.10)],
                                center: .center,
                                startRadius: 0,
                                endRadius: 100
                            )
                        )
                        .frame(width: BreathingVisualMetrics.breathingCircleSize, height: BreathingVisualMetrics.breathingCircleSize)
                        .scaleEffect(circleScale)
                        .animation(
                            state.isRunning ? .easeInOut(duration: animationDuration) : .default,
                            value: circleScale
                        )

                    // Text overlay
                    VStack(spacing: 4) {
                        Text(phaseLabel)
                            .font(.system(size: 18, weight: .light, design: .rounded))
                            .foregroundStyle(.white)
                            .id(phaseLabel)
                            .transition(.opacity)

                        Text(phaseSubLabel)
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.45))
                            .monospacedDigit()
                    }
                    .animation(.easeInOut(duration: 0.3), value: phaseLabel)
                }
                .frame(width: BreathingVisualMetrics.animationFrameSize, height: BreathingVisualMetrics.animationFrameSize)
                .contentShape(Rectangle())
                .onTapGesture {
                    // Tap to toggle controls visibility
                    showControlsBriefly()
                }

                Spacer()

                // ── Bottom controls ────────────────────────────────────────
                VStack(spacing: 12) {
                    if state.isRunning {
                        Text(formatTime(state.sessionSecondsRemaining))
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.5))
                            .padding(.bottom, 4)

                        Button("结束练习") {
                            withAnimation { state.stop() }
                        }
                        .buttonStyle(BreathingButtonStyle(isProminent: false))
                    } else {
                        Button("开始练习") {
                            state.start()
                            scheduleControlsHide()
                        }
                        .buttonStyle(BreathingButtonStyle(isProminent: true))
                    }
                }
                .padding(.bottom, BreathingVisualMetrics.bottomPadding)
                .opacity(controlsVisible ? 1 : 0)
                .animation(.easeInOut(duration: 0.4), value: controlsVisible)
            }
        }
        .frame(width: BreathingVisualMetrics.windowWidth, height: BreathingVisualMetrics.windowHeight)
        .colorScheme(.dark)
        .background(
            WindowAccessor { window in
                // Revert to stable shielding level
                window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
                window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            }
        )
        .onAppear {
            appState.isBreathingActive = true
            showControlsBriefly()
        }
        .onDisappear {
            state.stop()
            appState.isBreathingActive = false
            
            // BUGFIX: If window is closed directly, ensure state is restored
            if appState.currentState == .breathing {
                appState.cleanupShortBreathingLog()
                if appState.restRemaining > 0 {
                    appState.currentState = .resting
                } else {
                    appState.currentState = .working
                }
            }
        }
        .onChange(of: state.isRunning) { oldValue, newValue in
            if newValue {
                appState.currentState = .breathing
            } else {
                appState.cleanupShortBreathingLog()
                if appState.currentState == .breathing {
                    if appState.restRemaining > 0 {
                        appState.currentState = .resting
                    } else {
                        appState.currentState = .working
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func formatTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%02d:%02d", m, s)
    }

    private func showControlsBriefly() {
        controlsVisible = true
        controlsTimer?.invalidate()
        if state.isRunning {
            controlsTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { _ in
                Task { @MainActor in
                    withAnimation { controlsVisible = false }
                }
            }
        }
    }

    private func scheduleControlsHide() {
        controlsTimer?.invalidate()
        controlsTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { _ in
            Task { @MainActor in
                withAnimation { controlsVisible = false }
            }
        }
    }

    private func shortName(_ pattern: BreathingPattern) -> String {
        switch pattern.id {
        case "box": return "箱式"
        case "478": return "4-7-8"
        case "diaphragmatic": return "腹式"
        default: return pattern.name
        }
    }
}

// MARK: - Custom Button Style

private struct BreathingButtonStyle: ButtonStyle {
    let isProminent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .medium, design: .rounded))
            .foregroundStyle(isProminent ? .black : .white.opacity(0.7))
            .padding(.horizontal, 36)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(isProminent ? Color.orange : Color.white.opacity(0.12))
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Window Accessor
struct WindowAccessor: NSViewRepresentable {
    var onChange: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                onChange(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                onChange(window)
            }
        }
    }
}
