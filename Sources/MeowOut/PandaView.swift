import SwiftUI
import AppKit

public struct PandaCanvasView: View {
    public let pose: ClawdPose
    public let height: CGFloat
    public var isWalking: Bool = false
    public var now: TimeInterval
    public let eyeOffset: CGPoint

    private let followMouse: Bool = true
    
    public static let viewBoxW: CGFloat = 16
    public static let viewBoxH: CGFloat = 16

    public init(pose: ClawdPose, height: CGFloat, isWalking: Bool = false, now: TimeInterval, eyeOffset: CGPoint = .zero) {
        self.pose = pose
        self.height = height
        self.isWalking = isWalking
        self.now = now
        self.eyeOffset = eyeOffset
    }

    public var body: some View {
        Canvas(rendersAsynchronously: false) { ctx, size in
            renderPanda(ctx: ctx, size: size)
        }
        .frame(width: height * Self.viewBoxW / Self.viewBoxH, height: height)
    }

    private func renderPanda(ctx: GraphicsContext, size: CGSize) {
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
            lookOffset = CGPoint(x: eyeOffset.x * 1.0, y: eyeOffset.y * 0.5)
        }
        
        let swayX: CGFloat = isWalking ? CGFloat(sin(walkPhase * 2 * .pi)) * 0.3 : 0
        let bobY: CGFloat = isWalking && (walkPhase < 0.25 || (walkPhase >= 0.5 && walkPhase < 0.75)) ? 0.5 : 0
        let idleBobY: CGFloat = 0
        
        let mainOffset = CGPoint(x: swayX, y: bobY + idleBobY)
        
        let blackColor = Color(red: 40/255, green: 40/255, blue: 45/255)
        let whiteColor = Color.white
        let greenColor = Color(red: 120/255, green: 170/255, blue: 110/255)
        let redColor = Color(red: 220/255, green: 50/255, blue: 60/255)
        
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
        
        // Legs (Back & Front rendered together for simplicity)
        let leftLegPhase = calculateLegOffset(group: 0, phase: walkPhase)
        let rightLegPhase = calculateLegOffset(group: 1, phase: walkPhase)
        let legW: CGFloat = 2.5
        let legH: CGFloat = 2.5
        
        // Left Leg
        var legLPath = Path()
        legLPath.addRoundedRect(in: CGRect(x: 4.5 + leftLegPhase.x, y: 12 + leftLegPhase.y, width: legW, height: legH), cornerSize: CGSize(width: 1, height: 1))
        transformCtx.fill(legLPath, with: .color(blackColor))
        
        // Right Leg
        var legRPath = Path()
        legRPath.addRoundedRect(in: CGRect(x: 9 + rightLegPhase.x, y: 12 + rightLegPhase.y, width: legW, height: legH), cornerSize: CGSize(width: 1, height: 1))
        transformCtx.fill(legRPath, with: .color(blackColor))
        
        // Black Shoulder/Back Background (creates the panda "vest")
        var vestPath = Path()
        vestPath.addRoundedRect(in: CGRect(x: 3.5, y: 5.5 + headDy, width: 9, height: 8), cornerSize: CGSize(width: 4, height: 4))
        transformCtx.fill(vestPath, with: .color(blackColor))
        
        // White Belly
        var bellyPath = Path()
        bellyPath.addRoundedRect(in: CGRect(x: 4, y: 7.5 + headDy, width: 8, height: 6), cornerSize: CGSize(width: 3.5, height: 3.5))
        transformCtx.fill(bellyPath, with: .color(whiteColor))
        // Subtle inner shadow / border for belly definition
        transformCtx.stroke(bellyPath, with: .color(blackColor.opacity(0.05)), lineWidth: 0.5)

        // Arms
        let armY: CGFloat = 7.5 + headDy
        let armW: CGFloat = 2.5
        let armH: CGFloat = 4.5
        var armL = Path()
        armL.addRoundedRect(in: CGRect(x: 2.5, y: armY, width: armW, height: armH), cornerSize: CGSize(width: 1.2, height: 1.2))
        transformCtx.fill(armL, with: .color(blackColor))
        
        var armR = Path()
        armR.addRoundedRect(in: CGRect(x: 11, y: armY, width: armW, height: armH), cornerSize: CGSize(width: 1.2, height: 1.2))
        transformCtx.fill(armR, with: .color(blackColor))
        
        // Ears
        let earRadius: CGFloat = 3.6
        var earL = Path()
        earL.addEllipse(in: CGRect(x: 2, y: 1 + earDy, width: earRadius, height: earRadius))
        transformCtx.fill(earL, with: .color(blackColor))
        
        var earR = Path()
        earR.addEllipse(in: CGRect(x: 10.4, y: 1 + earDy, width: earRadius, height: earRadius))
        transformCtx.fill(earR, with: .color(blackColor))
        
        // Head (White)
        var headPath = Path()
        headPath.addRoundedRect(in: CGRect(x: 3, y: 2 + headDy, width: 10, height: 7.5), cornerSize: CGSize(width: 3.5, height: 3.5))
        transformCtx.fill(headPath, with: .color(whiteColor))
        // Head outline for crispness against white backgrounds
        transformCtx.stroke(headPath, with: .color(blackColor.opacity(0.08)), lineWidth: 0.5)
        
        // Face features
        let faceX = lookOffset.x * 0.8
        let faceY = headDy + lookOffset.y * 0.8
        
        // Eye Patches
        let patchW: CGFloat = 2.8
        let patchH: CGFloat = 3.4
        var patchL = Path()
        patchL.addEllipse(in: CGRect(x: 4.2 + faceX, y: 4.5 + faceY, width: patchW, height: patchH))
        // Rotate patch slightly
        var ctxPatchL = transformCtx
        ctxPatchL.translateBy(x: 4.2 + faceX + patchW/2, y: 4.5 + faceY + patchH/2)
        ctxPatchL.rotate(by: .degrees(15))
        ctxPatchL.translateBy(x: -(4.2 + faceX + patchW/2), y: -(4.5 + faceY + patchH/2))
        ctxPatchL.fill(patchL, with: .color(blackColor))
        
        var patchR = Path()
        patchR.addEllipse(in: CGRect(x: 9.0 + faceX, y: 4.5 + faceY, width: patchW, height: patchH))
        var ctxPatchR = transformCtx
        ctxPatchR.translateBy(x: 9.0 + faceX + patchW/2, y: 4.5 + faceY + patchH/2)
        ctxPatchR.rotate(by: .degrees(-15))
        ctxPatchR.translateBy(x: -(9.0 + faceX + patchW/2), y: -(4.5 + faceY + patchH/2))
        ctxPatchR.fill(patchR, with: .color(blackColor))
        
        // Pupils
        if isBlinking {
            // Blink lines
            var blinkL = Path()
            blinkL.move(to: CGPoint(x: 5.0 + faceX, y: 6.0 + faceY))
            blinkL.addLine(to: CGPoint(x: 6.2 + faceX, y: 6.0 + faceY))
            transformCtx.stroke(blinkL, with: .color(whiteColor), lineWidth: 0.6)
            
            var blinkR = Path()
            blinkR.move(to: CGPoint(x: 9.8 + faceX, y: 6.0 + faceY))
            blinkR.addLine(to: CGPoint(x: 11.0 + faceX, y: 6.0 + faceY))
            transformCtx.stroke(blinkR, with: .color(whiteColor), lineWidth: 0.6)
        } else {
            // Open eyes
            let pupilR: CGFloat = 1.0
            var pupilL = Path()
            pupilL.addEllipse(in: CGRect(x: 5.2 + faceX, y: 5.5 + faceY, width: pupilR, height: pupilR))
            transformCtx.fill(pupilL, with: .color(whiteColor))
            
            var pupilR_shape = Path()
            pupilR_shape.addEllipse(in: CGRect(x: 9.8 + faceX, y: 5.5 + faceY, width: pupilR, height: pupilR))
            transformCtx.fill(pupilR_shape, with: .color(whiteColor))
        }
        
        // Nose
        var nosePath = Path()
        nosePath.addEllipse(in: CGRect(x: 7.4 + faceX, y: 7.2 + faceY, width: 1.2, height: 0.8))
        transformCtx.fill(nosePath, with: .color(blackColor))
        
        // Bamboo Accessory (Held in right arm)
        var ctxBamboo = transformCtx
        ctxBamboo.translateBy(x: 12.5, y: 8.5)
        // Sway the bamboo a little while walking
        ctxBamboo.rotate(by: .degrees(-25 + (isWalking ? sin(walkPhase * 2 * .pi) * 10 : 0)))
        ctxBamboo.translateBy(x: -12.5, y: -8.5)
        
        // Bamboo stalk
        var bambooStalk = Path()
        bambooStalk.addRoundedRect(in: CGRect(x: 12.0, y: 4.5, width: 0.8, height: 6.0), cornerSize: CGSize(width: 0.4, height: 0.4))
        ctxBamboo.fill(bambooStalk, with: .color(greenColor))
        
        // Bamboo leaves
        var leaf1 = Path()
        leaf1.addEllipse(in: CGRect(x: 12.5, y: 5.0, width: 2.5, height: 1.0))
        var ctxLeaf1 = ctxBamboo
        ctxLeaf1.translateBy(x: 12.5, y: 5.0)
        ctxLeaf1.rotate(by: .degrees(-40))
        ctxLeaf1.translateBy(x: -12.5, y: -5.0)
        ctxLeaf1.fill(leaf1, with: .color(greenColor))
        
        var leaf2 = Path()
        leaf2.addEllipse(in: CGRect(x: 10.0, y: 6.5, width: 2.5, height: 1.0))
        var ctxLeaf2 = ctxBamboo
        ctxLeaf2.translateBy(x: 12.5, y: 7.0)
        ctxLeaf2.rotate(by: .degrees(20))
        ctxLeaf2.translateBy(x: -12.5, y: -7.0)
        ctxLeaf2.fill(leaf2, with: .color(greenColor))
        
        // Chinese Knot (Tiny red accent on the bamboo)
        var knot = Path()
        knot.addRoundedRect(in: CGRect(x: 11.9, y: 9.5, width: 1.0, height: 1.0), cornerSize: CGSize(width: 0.2, height: 0.2))
        ctxBamboo.fill(knot, with: .color(redColor))
        var tassel = Path()
        tassel.addRect(CGRect(x: 12.2, y: 10.5, width: 0.4, height: 1.2))
        ctxBamboo.fill(tassel, with: .color(redColor))
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

public struct PandaView: View, PetSpriteView {
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
            PandaCanvasView(pose: pose, height: height, isWalking: isWalking, now: timeline.date.timeIntervalSinceReferenceDate, eyeOffset: eyeOffset)
        }
    }
}
