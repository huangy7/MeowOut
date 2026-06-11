import SwiftUI
import AppKit

public struct PikaCanvasView: View {
    public let pose: ClawdPose
    public let height: CGFloat
    public var isWalking: Bool = false
    public var now: TimeInterval

    private let followMouse: Bool = true
    
    public static let viewBoxW: CGFloat = 16
    public static let viewBoxH: CGFloat = 16

    public init(pose: ClawdPose, height: CGFloat, isWalking: Bool = false, now: TimeInterval) {
        self.pose = pose
        self.height = height
        self.isWalking = isWalking
        self.now = now
    }

    public var body: some View {
        Canvas(rendersAsynchronously: false) { ctx, size in
            renderPika(ctx: ctx, size: size)
        }
        .frame(width: height * Self.viewBoxW / Self.viewBoxH, height: height)
    }

    private func renderPika(ctx: GraphicsContext, size: CGSize) {
        let u = min(size.width / Self.viewBoxW, size.height / Self.viewBoxH)
        
        let breatheT = sin(now * 2 * .pi / 3.2)
        let sx = 1.0 + CGFloat(breatheT) * 0.01
        let sy = 1.0 - CGFloat(breatheT) * 0.02
        
        let walkPhase = isWalking ? now.truncatingRemainder(dividingBy: 1.0) : 0
        let isBlinking = (now.truncatingRemainder(dividingBy: 4.0) / 4.0) > 0.95
        
        var lookOffset = CGPoint.zero
        var isStretch = false
        
        if pose == .armsUp { isStretch = true }
        else if pose == .lookLeft { lookOffset.x = -1 }
        else if pose == .lookRight { lookOffset.x = 1 }
        else if pose == .rest && followMouse {
            lookOffset = calculateMouseTracking()
        }
        
        let swayX: CGFloat = isWalking ? CGFloat(sin(walkPhase * 2 * .pi)) * 0.3 : 0
        let bobY: CGFloat = isWalking && (walkPhase < 0.25 || (walkPhase >= 0.5 && walkPhase < 0.75)) ? 0.5 : 0
        let idleBobY: CGFloat = 0
        
        let mainOffset = CGPoint(x: swayX, y: bobY + idleBobY)
        
        let blackColor = Color(red: 40/255, green: 40/255, blue: 45/255)
        let yellowColor = Color(red: 250/255, green: 214/255, blue: 61/255)
        let brownColor = Color(red: 140/255, green: 75/255, blue: 30/255)
        let redColor = Color(red: 236/255, green: 80/255, blue: 60/255)
        
        var transformCtx = ctx
        // Center the 16x16 viewbox
        let offsetX = (size.width - Self.viewBoxW * u) / 2
        let offsetY = (size.height - Self.viewBoxH * u) / 2
        transformCtx.translateBy(x: offsetX, y: offsetY)
        transformCtx.scaleBy(x: u, y: u)
        
        // Shadow
        let shadowRect = CGRect(x: 4, y: 14.5, width: 8, height: 1.5)
        transformCtx.fill(Path(ellipseIn: shadowRect), with: .color(.black.opacity(0.15)))
        
        // --- Apply Breathing Scale & Offset ---
        transformCtx.translateBy(x: 8 + mainOffset.x, y: 8 + mainOffset.y)
        transformCtx.scaleBy(x: sx, y: sy)
        transformCtx.translateBy(x: -8, y: -8)
        
        let earDy = isStretch ? -1.0 : 0.0
        let headDy = isStretch ? -0.5 : 0.0
        
        // Tail
        var tailCtx = transformCtx
        let tailBaseX: CGFloat = 3.0
        let tailBaseY: CGFloat = 11.0
        tailCtx.translateBy(x: tailBaseX, y: tailBaseY)
        // Tail wagging animation
        let tailWag = isWalking ? sin(walkPhase * 2 * .pi) * 15 : 0
        tailCtx.rotate(by: .degrees(tailWag - 10))
        tailCtx.translateBy(x: -tailBaseX, y: -tailBaseY)
        
        var tailPath = Path()
        tailPath.move(to: CGPoint(x: tailBaseX, y: tailBaseY))
        tailPath.addLine(to: CGPoint(x: tailBaseX - 2, y: tailBaseY - 1))
        tailPath.addLine(to: CGPoint(x: tailBaseX - 1.5, y: tailBaseY - 3))
        tailPath.addLine(to: CGPoint(x: tailBaseX - 4, y: tailBaseY - 4))
        tailPath.addLine(to: CGPoint(x: tailBaseX - 3.5, y: tailBaseY - 6))
        tailPath.addLine(to: CGPoint(x: tailBaseX - 1, y: tailBaseY - 5))
        tailPath.addLine(to: CGPoint(x: tailBaseX, y: tailBaseY))
        tailCtx.fill(tailPath, with: .color(yellowColor))
        tailCtx.stroke(tailPath, with: .color(brownColor), lineWidth: 0.5)

        // Legs
        let leftLegPhase = calculateLegOffset(group: 0, phase: walkPhase)
        let rightLegPhase = calculateLegOffset(group: 1, phase: walkPhase)
        let legW: CGFloat = 2.5
        let legH: CGFloat = 2.5
        
        // Left Leg
        var legLPath = Path()
        legLPath.addRect(CGRect(x: 4.5 + leftLegPhase.x, y: 12 + leftLegPhase.y, width: legW, height: legH))
        transformCtx.fill(legLPath, with: .color(yellowColor))
        
        // Right Leg
        var legRPath = Path()
        legRPath.addRect(CGRect(x: 9 + rightLegPhase.x, y: 12 + rightLegPhase.y, width: legW, height: legH))
        transformCtx.fill(legRPath, with: .color(yellowColor))
        
        // Body (Yellow Rectangle)
        var bodyPath = Path()
        bodyPath.addRect(CGRect(x: 4, y: 7.5 + headDy, width: 8, height: 6))
        transformCtx.fill(bodyPath, with: .color(yellowColor))
        
        // Brown stripes on back (simulated slightly visible on the edge)
        var stripePath = Path()
        stripePath.addRect(CGRect(x: 3.5, y: 9 + headDy, width: 1.5, height: 1.0))
        stripePath.addRect(CGRect(x: 3.5, y: 11 + headDy, width: 1.5, height: 1.0))
        transformCtx.fill(stripePath, with: .color(brownColor))

        // Arms
        let armY: CGFloat = 8.5 + headDy
        let armW: CGFloat = 2.0
        let armH: CGFloat = 3.5
        var armL = Path()
        armL.addRect(CGRect(x: 3.5, y: armY, width: armW, height: armH))
        transformCtx.fill(armL, with: .color(yellowColor))
        
        var armR = Path()
        armR.addRect(CGRect(x: 10.5, y: armY, width: armW, height: armH))
        transformCtx.fill(armR, with: .color(yellowColor))
        
        // Ears
        let earW: CGFloat = 2.0
        let earH: CGFloat = 5.0
        
        // Left Ear
        var ctxEarL = transformCtx
        ctxEarL.translateBy(x: 4, y: 2 + earDy)
        ctxEarL.rotate(by: .degrees(-25))
        ctxEarL.translateBy(x: -4, y: -(2 + earDy))
        
        var earL = Path()
        earL.addRect(CGRect(x: 3, y: -2 + earDy, width: earW, height: earH))
        ctxEarL.fill(earL, with: .color(yellowColor))
        var earLTip = Path()
        earLTip.addRect(CGRect(x: 3, y: -2 + earDy, width: earW, height: 1.5))
        ctxEarL.fill(earLTip, with: .color(blackColor))
        
        // Right Ear
        var ctxEarR = transformCtx
        ctxEarR.translateBy(x: 12, y: 2 + earDy)
        ctxEarR.rotate(by: .degrees(25))
        ctxEarR.translateBy(x: -12, y: -(2 + earDy))
        
        var earR = Path()
        earR.addRect(CGRect(x: 11, y: -2 + earDy, width: earW, height: earH))
        ctxEarR.fill(earR, with: .color(yellowColor))
        var earRTip = Path()
        earRTip.addRect(CGRect(x: 11, y: -2 + earDy, width: earW, height: 1.5))
        ctxEarR.fill(earRTip, with: .color(blackColor))
        
        // Head (Yellow Block)
        var headPath = Path()
        headPath.addRect(CGRect(x: 3, y: 2 + headDy, width: 10, height: 7))
        transformCtx.fill(headPath, with: .color(yellowColor))
        
        // Face features
        let faceX = lookOffset.x * 0.8
        let faceY = headDy + lookOffset.y * 0.8
        
        // Cheeks (Red rectangles)
        var cheekL = Path()
        cheekL.addRect(CGRect(x: 3.5 + faceX, y: 6.5 + faceY, width: 1.8, height: 1.5))
        transformCtx.fill(cheekL, with: .color(redColor))
        
        var cheekR = Path()
        cheekR.addRect(CGRect(x: 10.7 + faceX, y: 6.5 + faceY, width: 1.8, height: 1.5))
        transformCtx.fill(cheekR, with: .color(redColor))
        
        // Eyes (Black squares)
        if isBlinking {
            var blinkL = Path()
            blinkL.move(to: CGPoint(x: 5.0 + faceX, y: 5.5 + faceY))
            blinkL.addLine(to: CGPoint(x: 6.5 + faceX, y: 5.5 + faceY))
            transformCtx.stroke(blinkL, with: .color(blackColor), lineWidth: 0.8)
            
            var blinkR = Path()
            blinkR.move(to: CGPoint(x: 9.5 + faceX, y: 5.5 + faceY))
            blinkR.addLine(to: CGPoint(x: 11.0 + faceX, y: 5.5 + faceY))
            transformCtx.stroke(blinkR, with: .color(blackColor), lineWidth: 0.8)
        } else {
            var eyeL = Path()
            eyeL.addRect(CGRect(x: 5.0 + faceX, y: 4.5 + faceY, width: 1.5, height: 1.5))
            transformCtx.fill(eyeL, with: .color(blackColor))
            var pupilL = Path()
            pupilL.addRect(CGRect(x: 5.2 + faceX, y: 4.7 + faceY, width: 0.5, height: 0.5))
            transformCtx.fill(pupilL, with: .color(.white))
            
            var eyeR = Path()
            eyeR.addRect(CGRect(x: 9.5 + faceX, y: 4.5 + faceY, width: 1.5, height: 1.5))
            transformCtx.fill(eyeR, with: .color(blackColor))
            var pupilR = Path()
            pupilR.addRect(CGRect(x: 9.7 + faceX, y: 4.7 + faceY, width: 0.5, height: 0.5))
            transformCtx.fill(pupilR, with: .color(.white))
        }
        
        // Nose (Tiny dot)
        var nosePath = Path()
        nosePath.addRect(CGRect(x: 7.7 + faceX, y: 6.0 + faceY, width: 0.6, height: 0.4))
        transformCtx.fill(nosePath, with: .color(blackColor))
        
        // Mouth (Blocky inverted triangle or simple shape)
        var mouthPath = Path()
        mouthPath.move(to: CGPoint(x: 7.0 + faceX, y: 6.8 + faceY))
        mouthPath.addLine(to: CGPoint(x: 8.0 + faceX, y: 7.5 + faceY))
        mouthPath.addLine(to: CGPoint(x: 9.0 + faceX, y: 6.8 + faceY))
        transformCtx.stroke(mouthPath, with: .color(blackColor), lineWidth: 0.5)

        // Sparks
        if isWalking {
            let sparkCount = 3
            for i in 0..<sparkCount {
                let sparkSeed = floor(now * 8.0) + Double(i) * 3.14
                let sparkActive = abs(sin(sparkSeed * 123.456)) > 0.85
                if sparkActive {
                    let rx = sin(sparkSeed * 789.123) * 8
                    let ry = cos(sparkSeed * 456.789) * 8
                    let sparkSize: CGFloat = 1.0 + CGFloat(abs(sin(sparkSeed * 111.111))) * 1.5
                    
                    var sparkPath = Path()
                    let cx = 8 + rx
                    let cy = 8 + ry + headDy
                    // Draw a little plus sign or square for a blocky spark
                    sparkPath.addRect(CGRect(x: cx, y: cy, width: sparkSize, height: sparkSize))
                    
                    // Slightly rotate the spark
                    var ctxSpark = transformCtx
                    ctxSpark.translateBy(x: cx + sparkSize/2, y: cy + sparkSize/2)
                    ctxSpark.rotate(by: .degrees(sparkSeed * 50))
                    ctxSpark.translateBy(x: -(cx + sparkSize/2), y: -(cy + sparkSize/2))
                    
                    ctxSpark.fill(sparkPath, with: .color(.yellow))
                    ctxSpark.stroke(sparkPath, with: .color(.white), lineWidth: 0.3)
                }
            }
        }
    }
    
    private func calculateMouseTracking() -> CGPoint {
        let loc = NSEvent.mouseLocation
        guard let screen = NSScreen.main, screen.frame.contains(loc) else { return .zero }
        let nx = max(-1, min(1, (loc.x - screen.frame.midX) / (screen.frame.width / 2)))
        let ny = max(-1, min(1, (loc.y - screen.frame.midY) / (screen.frame.height / 2)))
        return CGPoint(x: CGFloat(nx) * 1.0, y: CGFloat(-ny) * 0.5)
    }
    
    private func calculateLegOffset(group: Int, phase: Double) -> CGPoint {
        guard isWalking else { return .zero }
        let p = phase
        if group == 0 {
            if p < 0.125 { return CGPoint(x: -0.5, y: 0) }
            if p < 0.375 { return .zero }
            if p < 0.625 { return CGPoint(x: 0.5, y: 0) }
            if p < 0.875 { return CGPoint(x: 0, y: -0.5) }
            return CGPoint(x: -0.5, y: 0)
        } else {
            if p < 0.125 { return CGPoint(x: 0.5, y: 0) }
            if p < 0.375 { return CGPoint(x: 0, y: -0.5) }
            if p < 0.625 { return CGPoint(x: -0.5, y: 0) }
            if p < 0.875 { return .zero }
            return CGPoint(x: 0.5, y: 0)
        }
    }
}

public struct PikaView: View, PetSpriteView {
    public let pose: ClawdPose
    public let height: CGFloat
    public var isWalking: Bool = false

    public init(pose: ClawdPose, height: CGFloat, isWalking: Bool = false) {
        self.pose = pose
        self.height = height
        self.isWalking = isWalking
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0/30.0)) { timeline in
            PikaCanvasView(pose: pose, height: height, isWalking: isWalking, now: timeline.date.timeIntervalSinceReferenceDate)
        }
    }
}
