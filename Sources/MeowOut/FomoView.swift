import SwiftUI

// Portions derived from HermesPet (https://github.com/basionwang-bot/HermesPet)
// Licensed under Apache 2.0 — see LICENSE.HermesPet
// Modifications: hardcoded colors, simplified to fit MeowOut 30fps TimelineView

public struct FomoCanvasView: View {
    public let pose: ClawdPose
    public let height: CGFloat
    public var isWalking: Bool = false
    public var now: TimeInterval

    public static let viewBoxW: CGFloat = 14
    public static let viewBoxH: CGFloat = 10

    private static let bodyColor       = Color(red: 0.97, green: 0.98, blue: 1.0)
    private static let bodyShadowColor = Color(red: 180.0/255, green: 197.0/255, blue: 232.0/255)
    private static let bodyLowColor    = Color(red: 150.0/255, green: 165.0/255, blue: 194.0/255)
    private static let pinkColor       = Color(red: 0.95, green: 0.72, blue: 0.82)
    
    private static let head     = FomoRect(x: 4,   y: 2,   w: 6,   h: 5)
    private static let leftEarBaseX:  CGFloat = 4.0
    private static let rightEarBaseX: CGFloat = 8.5
    private static let earBaseY:      CGFloat = 0.0
    private static let leftEye  = FomoRect(x: 5.2, y: 4.0, w: 1.0, h: 1.0)
    private static let rightEye = FomoRect(x: 7.8, y: 4.0, w: 1.0, h: 1.0)
    private static let nose     = FomoRect(x: 6.7, y: 5.4, w: 0.6, h: 0.5)
    private static let body     = FomoRect(x: 3,   y: 6.3, w: 8,   h: 2.5)
    private static let legs: [FomoRect] = [
        FomoRect(x: 3.5, y: 8.5, w: 1.0, h: 1.5),
        FomoRect(x: 5.5, y: 8.5, w: 1.0, h: 1.5),
        FomoRect(x: 7.5, y: 8.5, w: 1.0, h: 1.5),
        FomoRect(x: 9.5, y: 8.5, w: 1.0, h: 1.5),
    ]
    private static let shadow   = FomoRect(x: 3,   y: 9.7, w: 8,   h: 0.3)

    public init(pose: ClawdPose, height: CGFloat, isWalking: Bool = false, now: TimeInterval) {
        self.pose = pose
        self.height = height
        self.isWalking = isWalking
        self.now = now
    }

    public var body: some View {
        Canvas(rendersAsynchronously: false) { ctx, size in
            draw(ctx: ctx, size: size, now: now)
        }
        .frame(width: height * Self.viewBoxW / Self.viewBoxH, height: height)
    }

    private func draw(ctx: GraphicsContext, size: CGSize, now: TimeInterval) {
        let unit = min(size.width / Self.viewBoxW, size.height / Self.viewBoxH)

        let bodyFill   = GraphicsContext.Shading.color(Self.bodyColor)
        let bodyShadow = GraphicsContext.Shading.color(Self.bodyShadowColor)
        let bodyLow    = GraphicsContext.Shading.color(Self.bodyLowColor)
        let pinkFill   = GraphicsContext.Shading.color(Self.pinkColor)
        let eyeFill    = GraphicsContext.Shading.color(.black)
        let highlight  = GraphicsContext.Shading.color(.white)
        let ground     = GraphicsContext.Shading.color(.black.opacity(0.18))

        // 呼吸
        let breatheT = sin(now * 2 * .pi / 2.5)
        let breatheSY: CGFloat = 1 - CGFloat(breatheT) * 0.05

        // 走路
        let walkPhase = isWalking ? now.truncatingRemainder(dividingBy: 0.9) / 0.9 : 0
        let bobY: CGFloat = isWalking ? CGFloat(sin(now * 2 * .pi / 0.9)) * 0.25 : 0

        // 眨眼
        let blinkPhase = now.truncatingRemainder(dividingBy: 4.5) / 4.5
        let isBlinking = blinkPhase > 0.96

        // 耳朵灵动高频抖动
        let leftEarWiggleX  = CGFloat(sin(now * 2 * .pi * 1.6)) * 0.15
        let rightEarWiggleX = CGFloat(sin(now * 2 * .pi * 1.6 + .pi * 0.7)) * 0.15

        // 大幅 twitch
        let twitchCycle = 4.0
        let leftPh  = now.truncatingRemainder(dividingBy: twitchCycle) / twitchCycle
        let rightPh = (now + 0.8).truncatingRemainder(dividingBy: twitchCycle) / twitchCycle
        let leftEarTwitch: CGFloat = {
            guard leftPh < 0.038 else { return 0 }
            return CGFloat(sin(leftPh / 0.038 * .pi)) * 0.55
        }()
        let rightEarTwitch: CGFloat = {
            guard rightPh < 0.038 else { return 0 }
            return CGFloat(sin(rightPh / 0.038 * .pi)) * 0.50
        }()

        let earDownY: CGFloat = (pose == .armsUp) ? 0.5 : 0

        let (eyeLookX, _): (CGFloat, CGFloat) = {
            switch pose {
            case .lookLeft:  return (-0.3, 0)
            case .lookRight: return ( 0.3, 0)
            default:         return ( 0,   0)
            }
        }()

        var c = ctx
        // 水平镜像，默认朝右
        c.translateBy(x: size.width, y: 0)
        c.scaleBy(x: -1.0, y: 1.0)
        let cx = Self.viewBoxW / 2 * unit
        let cy = Self.viewBoxH / 2 * unit
        let idleBobY: CGFloat = isWalking ? 0 : CGFloat(breatheT) * 0.35
        c.translateBy(x: cx, y: cy + (bobY + idleBobY) * unit)
        c.scaleBy(x: 1.0, y: breatheSY)
        c.translateBy(x: -cx, y: -cy)

        func paint(_ r: FomoRect, _ shading: GraphicsContext.Shading) {
            let rect = CGRect(x: r.x * unit, y: r.y * unit, width: r.w * unit, height: r.h * unit)
            c.fill(Path(rect), with: shading)
        }

        // 1. 地面阴影
        paint(Self.shadow, ground)

        // 2. 尾巴
        let tailSwing: CGFloat = isWalking
            ? CGFloat(sin(now * 2 * .pi / 0.6)) * 0.5
            : CGFloat(sin(now * 2 * .pi / 2.5)) * 0.25
        let tailX = 10.5 + tailSwing
        paint(FomoRect(x: tailX,        y: 5.0, w: 2.5, h: 3.0), bodyFill)
        paint(FomoRect(x: tailX + 1.8,  y: 5.8, w: 1.5, h: 2.2), bodyFill)
        paint(FomoRect(x: tailX + 2.5,  y: 6.5, w: 1.0, h: 1.5), highlight)
        paint(FomoRect(x: tailX,        y: 7.2, w: 1.5, h: 1.0), bodyShadow)

        // 3. 身体
        paint(Self.body, bodyFill)
        paint(FomoRect(x: 3.5, y: 7.5, w: 7, h: 1), highlight)

        // 4. 四条腿
        for (i, leg) in Self.legs.enumerated() {
            let groupA = (i == 0 || i == 2)
            let phase = groupA ? walkPhase : (walkPhase + 0.5).truncatingRemainder(dividingBy: 1.0)
            let lift: CGFloat = isWalking && phase < 0.5
                ? -CGFloat(sin(phase * 2 * .pi)) * 0.35
                : 0
            paint(FomoRect(x: leg.x, y: leg.y + lift, w: leg.w, h: leg.h), bodyFill)
            paint(FomoRect(x: leg.x, y: leg.y + leg.h - 0.3 + lift, w: leg.w, h: 0.3), bodyShadow)
        }

        // 5. 头部
        paint(Self.head, bodyFill)
        paint(FomoRect(x: 4, y: 6.0, w: 6, h: 1.0), bodyShadow)
        paint(FomoRect(x: 4.5, y: 3.0, w: 1.2, h: 0.7), highlight)
        paint(FomoRect(x: 8.3, y: 3.0, w: 1.2, h: 0.7), highlight)

        // 6. 耳朵
        let lex = Self.leftEarBaseX + leftEarWiggleX + leftEarTwitch * 0.4
        let ley = Self.earBaseY + earDownY - leftEarTwitch * 0.3
        paint(FomoRect(x: lex,       y: ley + 2.0, w: 1.8, h: 1.0), bodyFill)
        paint(FomoRect(x: lex + 0.25, y: ley + 1.0, w: 1.3, h: 1.0), bodyFill)
        paint(FomoRect(x: lex + 0.55, y: ley,       w: 0.7, h: 1.0), bodyFill)
        paint(FomoRect(x: lex + 0.5, y: ley + 1.3, w: 0.8, h: 1.3), pinkFill)
        paint(FomoRect(x: lex + 0.7, y: ley,       w: 0.3, h: 0.4), bodyLow)

        let rex = Self.rightEarBaseX + rightEarWiggleX - rightEarTwitch * 0.4
        let rey = Self.earBaseY + earDownY - rightEarTwitch * 0.3
        paint(FomoRect(x: rex,       y: rey + 2.0, w: 1.8, h: 1.0), bodyFill)
        paint(FomoRect(x: rex + 0.25, y: rey + 1.0, w: 1.3, h: 1.0), bodyFill)
        paint(FomoRect(x: rex + 0.55, y: rey,       w: 0.7, h: 1.0), bodyFill)
        paint(FomoRect(x: rex + 0.5, y: rey + 1.3, w: 0.8, h: 1.3), pinkFill)
        paint(FomoRect(x: rex + 0.7, y: rey,       w: 0.3, h: 0.4), bodyLow)

        // 7. 眼睛
        if !isBlinking {
            paint(FomoRect(x: Self.leftEye.x  + eyeLookX, y: Self.leftEye.y,  w: Self.leftEye.w,  h: Self.leftEye.h), eyeFill)
            paint(FomoRect(x: Self.rightEye.x + eyeLookX, y: Self.rightEye.y, w: Self.rightEye.w, h: Self.rightEye.h), eyeFill)
            paint(FomoRect(x: Self.leftEye.x  + 0.5 + eyeLookX, y: Self.leftEye.y  + 0.2, w: 0.3, h: 0.4), highlight)
            paint(FomoRect(x: Self.rightEye.x + 0.5 + eyeLookX, y: Self.rightEye.y + 0.2, w: 0.3, h: 0.4), highlight)
        } else {
            paint(FomoRect(x: Self.leftEye.x,  y: Self.leftEye.y  + 0.45, w: Self.leftEye.w,  h: 0.2), eyeFill)
            paint(FomoRect(x: Self.rightEye.x, y: Self.rightEye.y + 0.45, w: Self.rightEye.w, h: 0.2), eyeFill)
        }

        // 8. 鼻子
        paint(Self.nose, pinkFill)
    }
}

public struct FomoView: View, PetSpriteView {
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
            FomoCanvasView(pose: pose, height: height, isWalking: isWalking, now: timeline.date.timeIntervalSinceReferenceDate)
        }
    }
}

private struct FomoRect {
    let x: CGFloat
    let y: CGFloat
    let w: CGFloat
    let h: CGFloat
}
