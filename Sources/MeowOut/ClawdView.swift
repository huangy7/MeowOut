import SwiftUI
import AppKit

public enum ClawdPose {
    case rest, lookLeft, lookRight, armsUp
    case sleeping, working, grooving
    case wallCling, wave
    case peeking
}

/// A clean room ASCII matrix rasterization engine for drawing pixel art sprites.
private struct AsciiSpriteEngine {
    static func rasterize(matrix: String, unit: CGFloat, scale: CGSize = CGSize(width: 1, height: 1)) -> Path {
        var path = Path()
        let lines = matrix.split(separator: "\n")
        for (row, line) in lines.enumerated() {
            for (col, char) in line.enumerated() {
                if char == "#" {
                    let rect = CGRect(
                        x: CGFloat(col) * unit * scale.width,
                        y: CGFloat(row) * unit * scale.height,
                        width: unit * scale.width,
                        height: unit * scale.height
                    )
                    path.addRect(rect)
                }
            }
        }
        return path
    }
}

public struct ClawdCanvasView: View {
    public let pose: ClawdPose
    public let height: CGFloat
    public var isWalking: Bool = false
    public var now: TimeInterval
    public let eyeOffset: CGPoint
    
    private let followMouse: Bool = true

    private static let bodyColor = Color(red: 222.0/255, green: 136.0/255, blue: 109.0/255)
    private static let bodyTopColor = Color(red: 240.0/255, green: 161.0/255, blue: 135.0/255)
    private static let bodyBottomColor = Color(red: 192.0/255, green: 110.0/255, blue: 86.0/255)
    
    // 15x10 logic grid
    public static let viewBoxW: CGFloat = 15
    public static let viewBoxH: CGFloat = 10
    private static let anchor = CGPoint(x: 7.5, y: 5.0)
    
    // ASCII Patterns for body parts
    private static let torsoGrid = """
    ###########
    ###########
    ###########
    ###########
    ###########
    ###########
    ###########
    """
    
    private static let armGrid = """
    ##
    ##
    """
    
    private static let legGrid = """
    #
    #
    """
    
    private static let eyeGrid = """
    #
    #
    """
    
    private static let shadowGrid = """
    #########
    """
    
    public init(pose: ClawdPose, height: CGFloat, isWalking: Bool = false, now: TimeInterval, eyeOffset: CGPoint = .zero) {
        self.pose = pose
        self.height = height
        self.isWalking = isWalking
        self.now = now
        self.eyeOffset = eyeOffset
    }

    public var body: some View {
        Canvas(rendersAsynchronously: false) { ctx, size in
            renderClawd(ctx: ctx, size: size)
        }
        .frame(width: height * Self.viewBoxW / Self.viewBoxH, height: height)
    }

    private func renderClawd(ctx: GraphicsContext, size: CGSize) {
        let u = min(size.width / Self.viewBoxW, size.height / Self.viewBoxH)
        
        var breatheCycle = 2.5
        var breatheAmpX: CGFloat = 0.03
        var breatheAmpY: CGFloat = 0.05
        
        if pose == .sleeping {
            breatheCycle = 4.0
            breatheAmpX = 0.05
            breatheAmpY = 0.12
        }
        
        let breathe = sin(now * 2 * .pi / breatheCycle)
        let sx = 1.0 + CGFloat(breathe) * breatheAmpX
        let sy = 1.0 - CGFloat(breathe) * breatheAmpY
        
        let walkPhase = isWalking ? now.truncatingRemainder(dividingBy: 1.0) : 0
        let isBlinking = (now.truncatingRemainder(dividingBy: 4.5) / 4.5) > 0.96
        
        // Pose overrides
        var lookOffset = CGPoint.zero
        var isStretch = false
        
        if pose == .armsUp { isStretch = true }
        else if pose == .lookLeft { lookOffset.x = -2 }
        else if pose == .lookRight { lookOffset.x = 2 }
        else if pose == .rest && followMouse {
            lookOffset = CGPoint(x: eyeOffset.x * 2.0, y: eyeOffset.y * 0.5)
        }
        
        let stretchSy = isStretch ? 1.10 : 1.0
        let stretchDy = isStretch ? -1.0 : 0.0
        let stretchArmDy = isStretch ? -3.0 : 0.0
        
        // Walk kinematics
        let isStepBob = isWalking && (walkPhase < 0.25 || (walkPhase >= 0.5 && walkPhase < 0.75))
        let bobY: CGFloat = isStepBob ? 1 : 0
        var swayX: CGFloat = isWalking ? CGFloat(sin(walkPhase * 2 * .pi)) * 0.4 : 0
        
        let armSwing = isStepBob ? -1.5 : 1.5
        var armWaveL: CGFloat = isWalking ? armSwing : 0
        var armWaveR: CGFloat = -armWaveL
        
        if pose == .working {
            armWaveL = CGFloat(sin(now * 15)) * 2
            armWaveR = CGFloat(cos(now * 15)) * 2
        } else if pose == .grooving {
            swayX += CGFloat(sin(now * 4)) * 1.5
            armWaveL = CGFloat(sin(now * 4)) * 1.5
            armWaveR = CGFloat(sin(now * 4)) * 1.5
        } else if pose == .wave {
            armWaveL = CGFloat(sin(now * 20)) * 4
        }
        
        let idleBobY: CGFloat = isWalking ? 0 : CGFloat(breathe) * 0.35
        
        let finalScale = CGSize(width: sx, height: sy * stretchSy)
        let finalOffset = CGPoint(x: swayX, y: bobY + stretchDy + idleBobY)
        
        // Shadow
        drawComponent(ctx, grid: Self.shadowGrid, pos: CGPoint(x: 3, y: 9), unit: u, offset: .zero, scale: CGSize(width: 1, height: 1), color: .black.opacity(0.5))
        
        // Legs
        let legX: [CGFloat] = [3, 5, 9, 11]
        for (i, x) in legX.enumerated() {
            let walkGrp = (i == 0 || i == 2) ? 0 : 1
            let offset = calculateLegOffset(group: walkGrp, phase: walkPhase)
            drawComponent(ctx, grid: Self.legGrid, pos: CGPoint(x: x, y: 7), unit: u, offset: offset, scale: finalScale, color: Self.bodyColor)
        }
        
        // Torso
        drawComponent(ctx, grid: Self.torsoGrid, pos: CGPoint(x: 2, y: 0), unit: u, offset: finalOffset, scale: finalScale, color: Self.bodyColor)
        drawComponent(ctx, grid: String(repeating: "#", count: 11), pos: CGPoint(x: 2, y: 0), unit: u, offset: finalOffset, scale: finalScale, color: Self.bodyTopColor)
        drawComponent(ctx, grid: String(repeating: "#", count: 11), pos: CGPoint(x: 2, y: 6), unit: u, offset: finalOffset, scale: finalScale, color: Self.bodyBottomColor)
        
        // Arms
        drawComponent(ctx, grid: Self.armGrid, pos: CGPoint(x: 0, y: 3), unit: u, offset: CGPoint(x: finalOffset.x, y: finalOffset.y + armWaveL + stretchArmDy), scale: finalScale, color: Self.bodyColor)
        drawComponent(ctx, grid: Self.armGrid, pos: CGPoint(x: 13, y: 3), unit: u, offset: CGPoint(x: finalOffset.x, y: finalOffset.y + armWaveR + stretchArmDy), scale: finalScale, color: Self.bodyColor)
        
        // Eyes
        let eyeOffset = CGPoint(x: finalOffset.x + lookOffset.x, y: finalOffset.y + lookOffset.y)
        if isBlinking || pose == .sleeping {
            drawComponent(ctx, grid: "#", pos: CGPoint(x: 4, y: 2.85), unit: u, offset: eyeOffset, scale: finalScale, color: .black, pixelScale: CGSize(width: finalScale.width, height: finalScale.height * 0.3))
            drawComponent(ctx, grid: "#", pos: CGPoint(x: 10, y: 2.85), unit: u, offset: eyeOffset, scale: finalScale, color: .black, pixelScale: CGSize(width: finalScale.width, height: finalScale.height * 0.3))
        } else {
            drawComponent(ctx, grid: Self.eyeGrid, pos: CGPoint(x: 4, y: 2), unit: u, offset: eyeOffset, scale: finalScale, color: .black)
            drawComponent(ctx, grid: Self.eyeGrid, pos: CGPoint(x: 10, y: 2), unit: u, offset: eyeOffset, scale: finalScale, color: .black)
            
            // Highlight
            drawComponent(ctx, grid: "#", pos: CGPoint(x: 4.05, y: 2.1), unit: u, offset: eyeOffset, scale: finalScale, color: .white, pixelScale: CGSize(width: finalScale.width * 0.4, height: finalScale.height * 0.4))
            drawComponent(ctx, grid: "#", pos: CGPoint(x: 10.05, y: 2.1), unit: u, offset: eyeOffset, scale: finalScale, color: .white, pixelScale: CGSize(width: finalScale.width * 0.4, height: finalScale.height * 0.4))
        }
    }
    
    private func drawComponent(_ ctx: GraphicsContext, grid: String, pos: CGPoint, unit: CGFloat, offset: CGPoint, scale: CGSize, color: Color, pixelScale: CGSize? = nil) {
        let absX = pos.x + offset.x
        let absY = pos.y + offset.y
        
        let screenX = (absX - Self.anchor.x) * scale.width * unit + Self.anchor.x * unit
        let screenY = (absY - Self.anchor.y) * scale.height * unit + Self.anchor.y * unit
        
        var transformCtx = ctx
        transformCtx.translateBy(x: screenX, y: screenY)
        
        let pScale = pixelScale ?? scale
        let path = AsciiSpriteEngine.rasterize(matrix: grid, unit: unit, scale: pScale)
        transformCtx.fill(path, with: .color(color))
    }
    
    private func calculateMouseTracking() -> CGPoint {
        let loc = NSEvent.mouseLocation
        guard let screen = NSScreen.main, screen.frame.contains(loc) else { return .zero }
        let nx = max(-1, min(1, (loc.x - screen.frame.midX) / (screen.frame.width / 2)))
        let ny = max(-1, min(1, (loc.y - screen.frame.midY) / (screen.frame.height / 2)))
        return CGPoint(x: CGFloat(nx) * 2.0, y: CGFloat(-ny) * 0.5)
    }
    
    private func calculateLegOffset(group: Int, phase: Double) -> CGPoint {
        guard isWalking else { return .zero }
        let p = phase
        if group == 0 {
            if p < 0.125 { return CGPoint(x: -2, y: 0) }
            if p < 0.375 { return .zero }
            if p < 0.625 { return CGPoint(x: 2, y: 0) }
            if p < 0.875 { return CGPoint(x: 0, y: -2) }
            return CGPoint(x: -2, y: 0)
        } else {
            if p < 0.125 { return CGPoint(x: 2, y: 0) }
            if p < 0.375 { return CGPoint(x: 0, y: -2) }
            if p < 0.625 { return CGPoint(x: -2, y: 0) }
            if p < 0.875 { return .zero }
            return CGPoint(x: 2, y: 0)
        }
    }
}

public struct ClawdView: View, PetSpriteView {
    public let pose: ClawdPose
    public let height: CGFloat
    public var isWalking: Bool = false
    public var eyeOffset: CGPoint = .zero

    public init(pose: ClawdPose, height: CGFloat, isWalking: Bool = false) {
        self.pose = pose
        self.height = height
        self.isWalking = isWalking
        self.eyeOffset = .zero
    }

    public init(pose: ClawdPose, height: CGFloat, isWalking: Bool, eyeOffset: CGPoint) {
        self.pose = pose
        self.height = height
        self.isWalking = isWalking
        self.eyeOffset = eyeOffset
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0/30.0)) { timeline in
            ClawdCanvasView(pose: pose, height: height, isWalking: isWalking, now: timeline.date.timeIntervalSinceReferenceDate, eyeOffset: eyeOffset)
        }
    }
}
