import SwiftUI

enum LauncherVisualMetrics {
    static let windowSize: CGFloat = 300
    static let ringSize: CGFloat = 260
    static let shadowPadding: CGFloat = 10
    static let innerRadiusRatio: CGFloat = 0.39
    static let outerRingStrokeOpacity: CGFloat = 0.30
    static let innerRingStrokeOpacity: CGFloat = 0.20
    static let showsDefaultSectorDividers = false
    static let defaultSectorStrokeOpacity: CGFloat = 0
    static let hoveredSectorFillOpacityDark: CGFloat = 0.16
    static let hoveredSectorFillOpacityLight: CGFloat = 0.22
    static var hoveredSectorFillOpacity: CGFloat { hoveredSectorFillOpacityDark }
    static let usesSystemPanelShadow = false
    static let iconSize: CGFloat = 32
    static let iconRadius: CGFloat = 90
    static let normalIconScale: CGFloat = 1.0
    static let hoveredIconScale: CGFloat = 1.04
    static let normalIconYOffset: CGFloat = 0
    static let hoveredIconYOffset: CGFloat = 0
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
    var innerRadiusRatio: CGFloat = LauncherVisualMetrics.innerRadiusRatio
    
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) / 2
        let innerRadius = outerRadius * innerRadiusRatio
        
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

struct DonutRingShape: Shape {
    var innerRadiusRatio: CGFloat = LauncherVisualMetrics.innerRadiusRatio

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) / 2
        let innerRadius = outerRadius * innerRadiusRatio

        var path = Path()
        path.addArc(center: center, radius: outerRadius, startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false)
        path.closeSubpath()
        path.addArc(center: center, radius: innerRadius, startAngle: .degrees(0), endAngle: .degrees(360), clockwise: true)
        path.closeSubpath()

        return path
    }
}

struct DonutRingBorders: View {
    var innerRadiusRatio: CGFloat = LauncherVisualMetrics.innerRadiusRatio
    var outerStrokeOpacity: CGFloat = LauncherVisualMetrics.outerRingStrokeOpacity
    var innerStrokeOpacity: CGFloat = LauncherVisualMetrics.innerRingStrokeOpacity
    var lineWidth: CGFloat = 0.6

    var body: some View {
        GeometryReader { geo in
            let outerRadius = min(geo.size.width, geo.size.height) / 2
            let innerRadius = outerRadius * innerRadiusRatio
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)

            ZStack {
                // 外边缘高光边框
                Circle()
                    .stroke(Color.primary.opacity(outerStrokeOpacity), lineWidth: lineWidth)
                    .frame(width: outerRadius * 2, height: outerRadius * 2)

                // 内边缘镂空孔高光边框
                Circle()
                    .stroke(Color.primary.opacity(innerStrokeOpacity), lineWidth: lineWidth)
                    .frame(width: innerRadius * 2, height: innerRadius * 2)
            }
            .position(center)
        }
        .allowsHitTesting(false)
    }
}

struct DonutRingBackground: View {
    var innerRadiusRatio: CGFloat = LauncherVisualMetrics.innerRadiusRatio
    var outerStrokeOpacity: CGFloat = LauncherVisualMetrics.outerRingStrokeOpacity
    var innerStrokeOpacity: CGFloat = LauncherVisualMetrics.innerRingStrokeOpacity

    var body: some View {
        DonutRingShape(innerRadiusRatio: innerRadiusRatio)
            .fill(.regularMaterial)
            .donutRingBorders(
                innerRadiusRatio: innerRadiusRatio,
                outerStrokeOpacity: outerStrokeOpacity,
                innerStrokeOpacity: innerStrokeOpacity
            )
            .allowsHitTesting(false)
    }
}

extension View {
    func donutRingBorders(
        innerRadiusRatio: CGFloat = LauncherVisualMetrics.innerRadiusRatio,
        outerStrokeOpacity: CGFloat = LauncherVisualMetrics.outerRingStrokeOpacity,
        innerStrokeOpacity: CGFloat = LauncherVisualMetrics.innerRingStrokeOpacity,
        lineWidth: CGFloat = 0.6
    ) -> some View {
        self.overlay(
            DonutRingBorders(
                innerRadiusRatio: innerRadiusRatio,
                outerStrokeOpacity: outerStrokeOpacity,
                innerStrokeOpacity: innerStrokeOpacity,
                lineWidth: lineWidth
            )
        )
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
    @Environment(\.colorScheme) private var colorScheme
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
                DonutRingBackground()
                    .allowsHitTesting(false)
                
                if count > 0 {
                    ForEach(0..<count, id: \.self) { i in
                        let angles = sectorAngles(for: i, total: count)
                        RingSector(startAngle: angles.start, endAngle: angles.end)
                            .fill(sectorFill(isHovered: hoveredSector == i))
                            .animation(.easeInOut(duration: 0.12), value: hoveredSector)
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
                        SectorItemView(index: i, descriptor: descriptors[i], total: count, isHovered: hoveredSector == i)
                            .allowsHitTesting(false)
                    }
                }
                
                if count == 0 {
                    Text(I18n.localized("launcher_ring_empty", language: appState.language))
                        .font(.system(size: 11, weight: .medium))
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 10)
                        .frame(maxWidth: LauncherVisualMetrics.ringSize * LauncherVisualMetrics.innerRadiusRatio)
                        .allowsHitTesting(false)
                } else if let feedbackDescriptor {
                    descriptorCenterView(feedbackDescriptor)
                        .frame(maxWidth: LauncherVisualMetrics.ringSize * LauncherVisualMetrics.innerRadiusRatio)
                        .allowsHitTesting(false)
                }

                LauncherMouseTrackingView(
                    sectorCount: count,
                    onSectorChange: { sector in
                        if sector != hoveredSector {
                            if sector != nil {
                                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                            }
                            withAnimation(.easeOut(duration: 0.12)) {
                                hoveredSector = sector
                            }
                        }
                    },
                    onClick: { index in
                        triggerSector(index, descriptors: descriptors)
                    }
                )
                .frame(width: LauncherVisualMetrics.ringSize, height: LauncherVisualMetrics.ringSize)
            }
            .frame(width: LauncherVisualMetrics.ringSize, height: LauncherVisualMetrics.ringSize)

            if appState.launcherRings.count > 1 {
                multiRingCapsule
                    .offset(y: (LauncherVisualMetrics.ringSize / 2) + 6)
            }
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

    @ViewBuilder
    private var multiRingCapsule: some View {
        HStack(spacing: 4) {
            Text(currentRing.name)
                .fontWeight(.semibold)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 80)
            Text("(\(appState.currentLauncherRingIndex + 1)/\(appState.launcherRings.count))")
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
            Text("·")
                .foregroundColor(.secondary)
            Text(I18n.localized("scroll_to_switch", language: appState.language))
                .font(.system(size: 9.5, weight: .regular))
                .foregroundColor(.secondary)
        }
        .font(.system(size: 11))
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.primary.opacity(0.12), lineWidth: 0.8))
        .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
        .allowsHitTesting(false)
    }

    private func sectorFill(isHovered: Bool) -> Color {
        let opacity = colorScheme == .dark
            ? LauncherVisualMetrics.hoveredSectorFillOpacityDark
            : LauncherVisualMetrics.hoveredSectorFillOpacityLight
        return Color.white.opacity(isHovered ? opacity : 0)
    }

    @ViewBuilder
    private func descriptorCenterView(_ descriptor: QuickToolActionDescriptor) -> some View {
        VStack(spacing: 2) {
            Text(descriptor.displayName)
                .font(.system(size: 11, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundColor(.primary)
                .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1)
            if let state = descriptor.state {
                Text(state.subtitle)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(state.isActive ? .green : .secondary)
                    .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1)
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

struct SectorItemView: View {
    @Environment(\.colorScheme) private var colorScheme

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

        VStack(spacing: 2.5) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let builtInType = descriptor.builtInType {
                        BuiltInToolIconView(type: builtInType, size: LauncherVisualMetrics.iconSize)
                    } else if let path = descriptor.appPath {
                        AppIconView(path: path, size: LauncherVisualMetrics.iconSize)
                    } else if let iconText = descriptor.iconText {
                        Text(iconText)
                            .font(.system(size: 20))
                    }
                }
                .frame(width: LauncherVisualMetrics.iconSize, height: LauncherVisualMetrics.iconSize)
                .shadow(
                    color: Color.black.opacity(isHovered ? 0.20 : 0.10),
                    radius: isHovered ? 3.5 : 2,
                    x: 0,
                    y: isHovered ? 2 : 1
                )

                if descriptor.state?.isActive == true {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                        .offset(x: 2, y: -2)
                }
            }
            .frame(width: LauncherVisualMetrics.iconSize, height: LauncherVisualMetrics.iconSize)

            Text(descriptor.displayName)
                .font(.system(size: 8.5, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 64, height: 12)
                .shadow(
                    color: colorScheme == .dark ? Color.black.opacity(0.6) : Color.white.opacity(0.85),
                    radius: 1,
                    x: 0,
                    y: 1
                )
        }
        .frame(width: 64, height: 48)
        .scaleEffect(isHovered ? LauncherVisualMetrics.hoveredIconScale : LauncherVisualMetrics.normalIconScale)
        .offset(x: xOffset, y: yOffset)
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}
