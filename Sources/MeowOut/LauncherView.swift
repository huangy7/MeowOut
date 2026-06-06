import SwiftUI

enum LauncherVisualMetrics {
    static let windowSize: CGFloat = 280
    static let ringSize: CGFloat = 236
    static let shadowPadding: CGFloat = 18
    static let centerSize: CGFloat = 104
    static let innerRadiusRatio: CGFloat = 0.44
    static let outerRingStrokeOpacity: CGFloat = 0.025
    static let showsDefaultSectorDividers = false
    static let defaultSectorStrokeOpacity: CGFloat = 0
    static let hoveredSectorFillOpacity: CGFloat = 0.08
    static let usesSystemPanelShadow = false
    static let iconSize: CGFloat = 54
    static let iconRadius: CGFloat = 84
    static let normalIconScale: CGFloat = 1.0
    static let hoveredIconScale: CGFloat = 1.14
    static let normalIconYOffset: CGFloat = 0
    static let hoveredIconYOffset: CGFloat = -7
    static let feedbackDelayNanoseconds: UInt64 = 600_000_000
}

enum LauncherMouseTrackingPolicy {
    static let acceptsFirstMouseClick = true
}

enum LauncherSelectionGeometry {
    static func sectorIndex(at point: CGPoint, in size: CGSize, count: Int) -> Int? {
        guard count > 0 else { return nil }

        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let dx = point.x - center.x
        let dy = point.y - center.y
        let distance = sqrt(dx * dx + dy * dy)
        let outerRadius = min(size.width, size.height) / 2
        let innerRadius = outerRadius * LauncherVisualMetrics.innerRadiusRatio

        guard distance >= innerRadius, distance <= outerRadius else { return nil }

        let angleDegrees = atan2(dy, dx) * 180 / .pi
        let clockwiseFromTop = (angleDegrees + 90 + 360).truncatingRemainder(dividingBy: 360)
        let step = 360 / CGFloat(count)
        let centeredAngle = (clockwiseFromTop + step / 2).truncatingRemainder(dividingBy: 360)

        return Int(floor(centeredAngle / step))
    }
}

struct RingSector: Shape {
    var startAngle: Angle
    var endAngle: Angle
    
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) / 2
        let innerRadius = outerRadius * LauncherVisualMetrics.innerRadiusRatio
        
        var path = Path()
        path.addArc(center: center, radius: outerRadius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        path.addLine(to: CGPoint(
            x: center.x + innerRadius * cos(CGFloat(endAngle.radians)),
            y: center.y + innerRadius * sin(CGFloat(endAngle.radians))
        ))
        path.addArc(center: center, radius: innerRadius, startAngle: endAngle, endAngle: startAngle, clockwise: true)
        path.closeSubpath()
        return path
    }
}

private struct LauncherMouseTrackingView: NSViewRepresentable {
    var sectorCount: Int
    var onSectorChange: (Int?) -> Void
    var onClick: (Int) -> Void

    func makeNSView(context: Context) -> LauncherMouseTrackingNSView {
        let view = LauncherMouseTrackingNSView()
        view.sectorCount = sectorCount
        view.onSectorChange = onSectorChange
        view.onClick = onClick
        return view
    }

    func updateNSView(_ nsView: LauncherMouseTrackingNSView, context: Context) {
        nsView.sectorCount = sectorCount
        nsView.onSectorChange = onSectorChange
        nsView.onClick = onClick
    }
}

private final class LauncherMouseTrackingNSView: NSView {
    var sectorCount: Int = 0 {
        didSet {
            updateSector(at: lastLocation)
        }
    }
    var onSectorChange: ((Int?) -> Void)?
    var onClick: ((Int) -> Void)?

    private var currentSector: Int?
    private var lastLocation: CGPoint?

    override var isFlipped: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateSectorFromCurrentMouseLocation()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateSectorFromCurrentMouseLocation()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }

    override func mouseMoved(with event: NSEvent) {
        updateSector(with: event)
    }

    override func mouseEntered(with event: NSEvent) {
        updateSector(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        lastLocation = nil
        setCurrentSector(nil)
    }

    override func mouseDown(with event: NSEvent) {
        updateSector(with: event)
        if let currentSector {
            onClick?(currentSector)
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        LauncherMouseTrackingPolicy.acceptsFirstMouseClick
    }

    private func updateSectorFromCurrentMouseLocation() {
        guard let window else {
            setCurrentSector(nil)
            return
        }

        let location = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        updateSector(at: bounds.contains(location) ? location : nil)
    }

    private func updateSector(with event: NSEvent) {
        updateSector(at: convert(event.locationInWindow, from: nil))
    }

    private func updateSector(at location: CGPoint?) {
        lastLocation = location
        guard let location else {
            setCurrentSector(nil)
            return
        }

        setCurrentSector(LauncherSelectionGeometry.sectorIndex(at: location, in: bounds.size, count: sectorCount))
    }

    private func setCurrentSector(_ sector: Int?) {
        guard currentSector != sector else { return }
        currentSector = sector
        onSectorChange?(sector)
    }
}

public struct LauncherView: View {
    @Bindable var appState: AppState
    var onClose: () -> Void
    
    @State private var hoveredSector: Int? = nil
    @State private var feedbackDescriptor: QuickToolActionDescriptor? = nil
    @State private var feedbackTask: Task<Void, Never>? = nil
    
    public init(appState: AppState, onClose: @escaping () -> Void) {
        self.appState = appState
        self.onClose = onClose
    }
    
    private var currentRing: LauncherRing {
        let rings = appState.launcherRings
        let idx = appState.currentLauncherRingIndex
        if idx >= 0 && idx < rings.count {
            return rings[idx]
        }
        return LauncherRing(name: "Ring 1")
    }
    
    private var activeTools: [QuickTool] {
        currentRing.tools
    }
    
    public var body: some View {
        let tools = activeTools
        let descriptors = tools.map { QuickToolActionResolver.descriptor(for: $0, appState: appState) }
        let count = descriptors.count
        
        ZStack {
            ZStack {
                Circle()
                    .fill(.regularMaterial)
                    .overlay(Circle().stroke(Color.primary.opacity(LauncherVisualMetrics.outerRingStrokeOpacity), lineWidth: 0.6))
                    .shadow(color: Color.black.opacity(0.20), radius: 22, x: 0, y: 16)
                    .shadow(color: Color.black.opacity(0.08), radius: 5, x: 0, y: 1)
                
                if count > 0 {
                    ForEach(0..<count, id: \.self) { i in
                        let angles = sectorAngles(for: i, total: count)
                        RingSector(startAngle: angles.start, endAngle: angles.end)
                            .fill(sectorFill(isHovered: hoveredSector == i))
                            .overlay(
                                RingSector(startAngle: angles.start, endAngle: angles.end)
                                    .stroke(Color.primary.opacity(LauncherVisualMetrics.defaultSectorStrokeOpacity), lineWidth: 1)
                            )
                    }
                    
                    if LauncherVisualMetrics.showsDefaultSectorDividers && count > 1 {
                        ForEach(0..<count, id: \.self) { i in
                            let step = 360.0 / Double(count)
                            let angle = Angle.degrees(-90.0 + (step / 2.0) + Double(i) * step)
                            GeometryReader { geo in
                                let c = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                                let outerRadius = min(geo.size.width, geo.size.height) / 2
                                let innerRadius = outerRadius * LauncherVisualMetrics.innerRadiusRatio
                                
                                Path { path in
                                    path.move(to: CGPoint(
                                        x: c.x + innerRadius * cos(CGFloat(angle.radians)),
                                        y: c.y + innerRadius * sin(CGFloat(angle.radians))
                                    ))
                                    path.addLine(to: CGPoint(
                                        x: c.x + outerRadius * cos(CGFloat(angle.radians)),
                                        y: c.y + outerRadius * sin(CGFloat(angle.radians))
                                    ))
                                }
                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                            }
                        }
                    }
                    
                    ForEach(0..<count, id: \.self) { i in
                        SectorIconView(index: i, descriptor: descriptors[i], total: count, isHovered: hoveredSector == i)
                            .allowsHitTesting(false)
                    }
                }
                
                Circle()
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.97))
                    .frame(width: LauncherVisualMetrics.centerSize, height: LauncherVisualMetrics.centerSize)
                    .overlay(Circle().stroke(Color.primary.opacity(0.06), lineWidth: 0.8))
                    .shadow(color: Color.black.opacity(0.14), radius: 12, x: 0, y: 6)
                    .overlay(
                        VStack(spacing: 4) {
                            if count == 0 {
                                Text(I18n.localized("launcher_ring_empty", language: appState.language))
                                    .font(.system(size: 11, weight: .bold))
                                    .multilineTextAlignment(.center)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 8)
                            } else if let feedbackDescriptor {
                                descriptorCenterView(feedbackDescriptor)
                            } else if let idx = hoveredSector, idx < count {
                                descriptorCenterView(descriptors[idx])
                            } else {
                                Text(currentRing.name)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.secondary)
                                
                                if appState.launcherRings.count > 1 {
                                    Text("\(appState.currentLauncherRingIndex + 1)/\(appState.launcherRings.count)")
                                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    )
                    .allowsHitTesting(false)

                LauncherMouseTrackingView(
                    sectorCount: count,
                    onSectorChange: { sector in
                        withAnimation(.easeOut(duration: 0.12)) {
                            hoveredSector = sector
                        }
                    },
                    onClick: { index in
                        triggerSector(index, descriptors: descriptors)
                    }
                )
                .frame(width: LauncherVisualMetrics.ringSize, height: LauncherVisualMetrics.ringSize)
            }
            .frame(width: LauncherVisualMetrics.ringSize, height: LauncherVisualMetrics.ringSize)
        }
        .frame(width: LauncherVisualMetrics.windowSize, height: LauncherVisualMetrics.windowSize)
        .onAppear {
            if hoveredSector != nil && hoveredSector! >= count {
                hoveredSector = nil
            }
        }
        .onChange(of: count) { _, newCount in
            if hoveredSector != nil && hoveredSector! >= newCount {
                hoveredSector = nil
            }
        }
        .onDisappear {
            feedbackTask?.cancel()
            feedbackTask = nil
        }
    }

    private func sectorFill(isHovered: Bool) -> some ShapeStyle {
        if isHovered {
            return AnyShapeStyle(Color.primary.opacity(LauncherVisualMetrics.hoveredSectorFillOpacity))
        }
        return AnyShapeStyle(Color.clear)
    }

    @ViewBuilder
    private func descriptorCenterView(_ descriptor: QuickToolActionDescriptor) -> some View {
        VStack(spacing: 2) {
            Text(descriptor.displayName)
                .font(.system(size: 11, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundColor(.primary)
            if let state = descriptor.state {
                Text(state.subtitle)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(state.isActive ? .green : .secondary)
            }
        }
        .padding(.horizontal, 8)
    }
    
    private func sectorAngles(for i: Int, total: Int) -> (start: Angle, end: Angle) {
        let step = 360.0 / Double(total)
        let start = Angle.degrees(-90.0 - (step / 2.0) + Double(i) * step)
        let end = Angle.degrees(-90.0 + (step / 2.0) + Double(i) * step)
        return (start, end)
    }
    
    public func triggerHoveredSector() {
        if let idx = hoveredSector {
            let descriptors = activeTools.map { QuickToolActionResolver.descriptor(for: $0, appState: appState) }
            if idx < descriptors.count {
                triggerSector(idx, descriptors: descriptors)
            }
        }
    }
    
    private func triggerSector(_ i: Int, descriptors: [QuickToolActionDescriptor]) {
        guard i < descriptors.count else { return }
        let descriptor = descriptors[i]

        descriptor.execute()
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)

        switch descriptor.postExecutionBehavior {
        case .closeImmediately:
            onClose()
        case .showFeedbackThenClose:
            let updatedDescriptor = QuickToolActionResolver.descriptor(for: activeTools[i], appState: appState)
            feedbackDescriptor = updatedDescriptor
            feedbackTask?.cancel()
            feedbackTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: LauncherVisualMetrics.feedbackDelayNanoseconds)
                guard !Task.isCancelled else { return }
                feedbackDescriptor = nil
                onClose()
            }
        }
    }
}

struct SectorIconView: View {
    let index: Int
    let descriptor: QuickToolActionDescriptor
    let total: Int
    let isHovered: Bool
    
    var body: some View {
        let step = 360.0 / Double(total)
        let angle = Angle.degrees(-90.0 + Double(index) * step)
        let radius = LauncherVisualMetrics.iconRadius
        let xOffset = radius * cos(CGFloat(angle.radians))
        let yOffset = radius * sin(CGFloat(angle.radians))
        
        ZStack(alignment: .topTrailing) {
            Group {
                if let iconText = descriptor.iconText {
                    Text(iconText)
                        .font(.system(size: 23))
                } else if let path = descriptor.appPath {
                    AppIconView(path: path)
                }
            }
            .frame(width: LauncherVisualMetrics.iconSize, height: LauncherVisualMetrics.iconSize)
            .shadow(color: Color.black.opacity(isHovered ? 0.2 : 0.1), radius: isHovered ? 6 : 4, x: 0, y: isHovered ? 4 : 2)

            if descriptor.state?.isActive == true {
                Circle()
                    .fill(Color.green)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 2))
                    .offset(x: 2, y: -2)
            }
        }
        .scaleEffect(isHovered ? LauncherVisualMetrics.hoveredIconScale : LauncherVisualMetrics.normalIconScale)
        .offset(x: xOffset, y: yOffset + (isHovered ? LauncherVisualMetrics.hoveredIconYOffset : LauncherVisualMetrics.normalIconYOffset))
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}
