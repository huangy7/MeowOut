import SwiftUI
import AppKit

/// Clawd 的 pose 状态。
public enum ClawdPose {
    case rest, lookLeft, lookRight, armsUp
}

/// Clawd sprite 的一个像素矩形组件。
struct ClawdRect {
    let x: CGFloat
    let y: CGFloat
    let w: CGFloat
    let h: CGFloat
}

// Portions derived from HermesPet (https://github.com/basionwang-bot/HermesPet)
// Licensed under Apache 2.0 — see LICENSE.HermesPet
// Modifications: hardcoded colors, simplified animation parameters
public struct ClawdView: View, PetSpriteView {
    public let pose: ClawdPose
    public let height: CGFloat
    public var isWalking: Bool = false
    private let followMouse: Bool = true

    private static let bodyColor = Color(red: 222.0/255, green: 136.0/255, blue: 109.0/255)
    private static let bodyTopColor = Color(red: 240.0/255, green: 161.0/255, blue: 135.0/255)
    private static let bodyBottomColor = Color(red: 192.0/255, green: 110.0/255, blue: 86.0/255)
    private static let viewBoxW: CGFloat = 15
    private static let viewBoxH: CGFloat = 10
    private static let centerX: CGFloat = 7.5
    private static let centerY: CGFloat = 5.0

    private static let torso     = ClawdRect(x: 2,  y: 0, w: 11, h: 7)
    private static let leftArm   = ClawdRect(x: 0,  y: 3, w: 2,  h: 2)
    private static let rightArm  = ClawdRect(x: 13, y: 3, w: 2,  h: 2)
    private static let legs: [ClawdRect] = [
        ClawdRect(x: 3,  y: 7, w: 1, h: 2),
        ClawdRect(x: 5,  y: 7, w: 1, h: 2),
        ClawdRect(x: 9,  y: 7, w: 1, h: 2),
        ClawdRect(x: 11, y: 7, w: 1, h: 2),
    ]
    private static let leftEye  = ClawdRect(x: 4,  y: 2, w: 1, h: 2)
    private static let rightEye = ClawdRect(x: 10, y: 2, w: 1, h: 2)
    private static let shadow   = ClawdRect(x: 3,  y: 9, w: 9, h: 1)

    public init(pose: ClawdPose, height: CGFloat, isWalking: Bool = false) {
        self.pose = pose
        self.height = height
        self.isWalking = isWalking
    }

    public var body: some View {
        // 🔥 性能平衡：从 15 FPS 提升到 30 FPS。30 帧是视觉丝滑的黄金分割点，比 60 帧省电一半。
        TimelineView(.animation(minimumInterval: 1.0/30.0)) { timeline in
            Canvas(rendersAsynchronously: false) { ctx, size in
                draw(ctx: ctx, size: size, now: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
        .frame(width: height * Self.viewBoxW / Self.viewBoxH, height: height)
    }

    private func draw(ctx: GraphicsContext, size: CGSize, now: TimeInterval) {
        let unit = min(size.width / Self.viewBoxW, size.height / Self.viewBoxH)
        let bodyFill = GraphicsContext.Shading.color(Self.bodyColor)
        let bodyTopShading = GraphicsContext.Shading.color(Self.bodyTopColor)
        let bodyBottomShading = GraphicsContext.Shading.color(Self.bodyBottomColor)
        let eyeFill  = GraphicsContext.Shading.color(.black)
        let highlightFill = GraphicsContext.Shading.color(.white)
        let shadowFill = GraphicsContext.Shading.color(.black.opacity(0.5))

        let breatheT = sin(now * 2 * .pi / 3.2)
        let breatheSX: CGFloat = 1 + CGFloat(breatheT) * 0.02
        let breatheSY: CGFloat = 1 - CGFloat(breatheT) * 0.02

        let walkPhase = isWalking ? now.truncatingRemainder(dividingBy: 1.0) : 0
        let blinkCycle = 4.5
        let blinkPhase = now.truncatingRemainder(dividingBy: blinkCycle) / blinkCycle
        let isBlinking = blinkPhase > 0.96

        let (eyeLookX, eyeLookY): (CGFloat, CGFloat) = {
            switch pose {
            case .lookLeft:  return (-2, 0)
            case .lookRight: return ( 2, 0)
            case .armsUp:    return ( 0, 0)
            case .rest:
                guard followMouse else { return (0, 0) }
                return Self.continuousMouseEyeOffset()
            }
        }()

        let stretching = (pose == .armsUp)
        let stretchSX: CGFloat = stretching ? 0.95 : 1.0
        let stretchSY: CGFloat = stretching ? 1.10 : 1.0
        let stretchDY: CGFloat = stretching ? -1.0 : 0.0
        let armRaise:  CGFloat = stretching ? -3.0 : 0.0

        let bodyBobY: CGFloat = isWalking
            ? ((walkPhase < 0.25 || (walkPhase >= 0.5 && walkPhase < 0.75)) ? 1 : 0)
            : 0

        let walkSwayX: CGFloat = isWalking
            ? CGFloat(sin(walkPhase * 2 * .pi)) * 0.4
            : 0

        let armSwingAmount: CGFloat = 1.5
        let armWaveL: CGFloat = isWalking
            ? ((walkPhase < 0.25 || (walkPhase >= 0.5 && walkPhase < 0.75)) ? -armSwingAmount : armSwingAmount)
            : 0
        let armWaveR: CGFloat = -armWaveL

        let totalSX = breatheSX * stretchSX
        let totalSY = breatheSY * stretchSY
        let totalDY = bodyBobY + stretchDY
        let totalDX = walkSwayX

        drawRect(Self.shadow, in: ctx, unit: unit, offsetX: 0, offsetY: 0, scaleX: 1, scaleY: 1, fill: shadowFill)

        for (idx, leg) in Self.legs.enumerated() {
            let (lx, ly) = legOffset(group: (idx == 0 || idx == 2) ? 0 : 1, phase: walkPhase)
            drawRect(leg, in: ctx, unit: unit, offsetX: lx, offsetY: ly, scaleX: totalSX, scaleY: totalSY, fill: bodyFill)
        }

        drawRect(Self.torso, in: ctx, unit: unit, offsetX: totalDX, offsetY: totalDY, scaleX: totalSX, scaleY: totalSY, fill: bodyFill)
        drawRect(ClawdRect(x: Self.torso.x, y: Self.torso.y, w: Self.torso.w, h: 1), in: ctx, unit: unit, offsetX: totalDX, offsetY: totalDY, scaleX: totalSX, scaleY: totalSY, fill: bodyTopShading)
        drawRect(ClawdRect(x: Self.torso.x, y: Self.torso.y + Self.torso.h - 1, w: Self.torso.w, h: 1), in: ctx, unit: unit, offsetX: totalDX, offsetY: totalDY, scaleX: totalSX, scaleY: totalSY, fill: bodyBottomShading)

        drawRect(Self.leftArm, in: ctx, unit: unit, offsetX: totalDX, offsetY: totalDY + armWaveL + armRaise, scaleX: totalSX, scaleY: totalSY, fill: bodyFill)
        drawRect(Self.rightArm, in: ctx, unit: unit, offsetX: totalDX, offsetY: totalDY + armWaveR + armRaise, scaleX: totalSX, scaleY: totalSY, fill: bodyFill)

        let totalEyeDX = totalDX + eyeLookX
        let totalEyeDY = totalDY + eyeLookY
        if isBlinking {
            let centerEyeY = Self.leftEye.y + Self.leftEye.h / 2
            let blinkH: CGFloat = 0.3
            let blinkY = centerEyeY - blinkH / 2
            drawRect(ClawdRect(x: Self.leftEye.x,  y: blinkY, w: 1, h: blinkH), in: ctx, unit: unit, offsetX: totalEyeDX, offsetY: totalEyeDY, scaleX: totalSX, scaleY: totalSY, fill: eyeFill)
            drawRect(ClawdRect(x: Self.rightEye.x, y: blinkY, w: 1, h: blinkH), in: ctx, unit: unit, offsetX: totalEyeDX, offsetY: totalEyeDY, scaleX: totalSX, scaleY: totalSY, fill: eyeFill)
        } else {
            drawRect(Self.leftEye, in: ctx, unit: unit, offsetX: totalEyeDX, offsetY: totalEyeDY, scaleX: totalSX, scaleY: totalSY, fill: eyeFill)
            drawRect(Self.rightEye, in: ctx, unit: unit, offsetX: totalEyeDX, offsetY: totalEyeDY, scaleX: totalSX, scaleY: totalSY, fill: eyeFill)
            let hlW: CGFloat = 0.4
            let hlH: CGFloat = 0.4
            let hlDX: CGFloat = 0.05
            let hlDY: CGFloat = 0.1
            drawRect(ClawdRect(x: Self.leftEye.x + hlDX, y: Self.leftEye.y + hlDY, w: hlW, h: hlH), in: ctx, unit: unit, offsetX: totalEyeDX, offsetY: totalEyeDY, scaleX: totalSX, scaleY: totalSY, fill: highlightFill)
            drawRect(ClawdRect(x: Self.rightEye.x + hlDX, y: Self.rightEye.y + hlDY, w: hlW, h: hlH), in: ctx, unit: unit, offsetX: totalEyeDX, offsetY: totalEyeDY, scaleX: totalSX, scaleY: totalSY, fill: highlightFill)
        }
    }

    private static func continuousMouseEyeOffset() -> (CGFloat, CGFloat) {
        let loc = NSEvent.mouseLocation
        let screen = NSScreen.main
        guard let screen, screen.frame.contains(loc) else { return (0, 0) }
        let halfW = screen.frame.width / 2
        let halfH = screen.frame.height / 2
        let nx = max(-1, min(1, (loc.x - screen.frame.midX) / halfW))
        let ny = max(-1, min(1, (loc.y - screen.frame.midY) / halfH))
        return (CGFloat(nx) * 2.0, CGFloat(-ny) * 0.5)
    }

    private func legOffset(group: Int, phase: Double) -> (CGFloat, CGFloat) {
        guard isWalking else { return (0, 0) }
        let p = phase
        if group == 0 {
            if p < 0.125 { return (-2, 0) }
            if p < 0.375 { return ( 0, 0) }
            if p < 0.625 { return ( 2, 0) }
            if p < 0.875 { return ( 0, -2) }
            return (-2, 0)
        } else {
            if p < 0.125 { return ( 2, 0) }
            if p < 0.375 { return ( 0, -2) }
            if p < 0.625 { return (-2, 0) }
            if p < 0.875 { return ( 0, 0) }
            return ( 2, 0)
        }
    }

    private func drawRect(_ r: ClawdRect, in ctx: GraphicsContext, unit: CGFloat,
                          offsetX: CGFloat, offsetY: CGFloat,
                          scaleX: CGFloat, scaleY: CGFloat,
                          fill: GraphicsContext.Shading) {
        let rx = r.x + offsetX
        let ry = r.y + offsetY
        let screenX = (rx - Self.centerX) * scaleX * unit + Self.centerX * unit
        let screenY = (ry - Self.centerY) * scaleY * unit + Self.centerY * unit
        let screenW = r.w * scaleX * unit
        let screenH = r.h * scaleY * unit
        ctx.fill(Path(CGRect(x: screenX, y: screenY, width: screenW, height: screenH)), with: fill)
    }
}
