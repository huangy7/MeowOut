import SwiftUI

// Portions derived from HermesPet (https://github.com/basionwang-bot/HermesPet)
// Licensed under Apache 2.0 — see LICENSE.HermesPet
// Modifications: hardcoded colors, removed glasses feature, simplified draw

public struct CloudCanvasView: View {
    public let pose: ClawdPose
    public let height: CGFloat
    public var isWalking: Bool = false
    public var now: TimeInterval

    private static let bodyColor       = Color(red: 75.0/255, green: 0.0/255,   blue: 130.0/255) // Indigo
    private static let bodyTopColor    = Color(red: 100.0/255, green: 50.0/255,  blue: 180.0/255)
    private static let bodyBottomColor = Color(red: 50.0/255,  green: 0.0/255,   blue: 80.0/255)
    
    public static let viewBoxW: CGFloat = 14
    public static let viewBoxH: CGFloat = 10

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
        let topFill    = GraphicsContext.Shading.color(Self.bodyTopColor)
        let bottomFill = GraphicsContext.Shading.color(Self.bodyBottomColor)
        let eyeFill    = GraphicsContext.Shading.color(.white)
        let pupilFill  = GraphicsContext.Shading.color(.black)
        let shadowFill = GraphicsContext.Shading.color(.black.opacity(0.3))

        // 呼吸：上下浮动
        let breatheT = sin(now * 2 * .pi / 3.5)
        let floatY: CGFloat = CGFloat(breatheT) * 0.4

        // 走路摇摆
        let swayX: CGFloat = isWalking ? CGFloat(sin(now * 2 * .pi / 0.8)) * 0.3 : 0

        // 眨眼
        let blinkCycle = 5.0
        let blinkPhase = now.truncatingRemainder(dividingBy: blinkCycle) / blinkCycle
        let isBlinking = blinkPhase > 0.96

        // 眼神偏移
        let eyeLookX: CGFloat = {
            switch pose {
            case .lookLeft: return -1.5
            case .lookRight: return 1.5
            case .armsUp, .rest: return 0
            }
        }()

        let dy = floatY
        let dx = swayX

        // 阴影（椭圆，固定在底部）
        let shadowRect = CGRect(
            x: (3) * unit, y: 9 * unit,
            width: 8 * unit, height: 1 * unit
        )
        ctx.fill(Path(ellipseIn: shadowRect), with: shadowFill)

        // 云朵主体
        fillRect(x: 2 + dx, y: 4 + dy, w: 10, h: 4, ctx: ctx, unit: unit, fill: bodyFill)
        fillRect(x: 3 + dx, y: 2 + dy, w: 8, h: 3, ctx: ctx, unit: unit, fill: bodyFill)
        fillRect(x: 1 + dx, y: 5 + dy, w: 2, h: 2, ctx: ctx, unit: unit, fill: bodyFill)
        fillRect(x: 11 + dx, y: 5 + dy, w: 2, h: 2, ctx: ctx, unit: unit, fill: bodyFill)
        
        // 顶部高光
        fillRect(x: 4 + dx, y: 2 + dy, w: 6, h: 1, ctx: ctx, unit: unit, fill: topFill)
        // 底部阴影
        fillRect(x: 3 + dx, y: 7 + dy, w: 8, h: 1, ctx: ctx, unit: unit, fill: bottomFill)

        // 小脚（走路时交替抬放）
        let walkPhase = isWalking ? now.truncatingRemainder(dividingBy: 0.8) / 0.8 : 0
        let leftFootDY: CGFloat = isWalking ? (walkPhase < 0.5 ? -0.5 : 0) : 0
        let rightFootDY: CGFloat = isWalking ? (walkPhase >= 0.5 ? -0.5 : 0) : 0
        fillRect(x: 4 + dx, y: 8 + dy + leftFootDY, w: 2, h: 1, ctx: ctx, unit: unit, fill: bodyFill)
        fillRect(x: 8 + dx, y: 8 + dy + rightFootDY, w: 2, h: 1, ctx: ctx, unit: unit, fill: bodyFill)

        // 眼睛
        let eyeY: CGFloat = 4 + dy
        let leftEyeX: CGFloat = 4.5 + dx + eyeLookX * 0.3
        let rightEyeX: CGFloat = 8.5 + dx + eyeLookX * 0.3

        if isBlinking {
            fillRect(x: leftEyeX, y: eyeY + 0.7, w: 1.5, h: 0.3, ctx: ctx, unit: unit, fill: pupilFill)
            fillRect(x: rightEyeX, y: eyeY + 0.7, w: 1.5, h: 0.3, ctx: ctx, unit: unit, fill: pupilFill)
        } else {
            fillRect(x: leftEyeX, y: eyeY, w: 1.8, h: 1.8, ctx: ctx, unit: unit, fill: eyeFill)
            fillRect(x: rightEyeX, y: eyeY, w: 1.8, h: 1.8, ctx: ctx, unit: unit, fill: eyeFill)
            let pupilDX = eyeLookX * 0.15
            fillRect(x: leftEyeX + 0.5 + pupilDX, y: eyeY + 0.5, w: 1.0, h: 1.0, ctx: ctx, unit: unit, fill: pupilFill)
            fillRect(x: rightEyeX + 0.5 + pupilDX, y: eyeY + 0.5, w: 1.0, h: 1.0, ctx: ctx, unit: unit, fill: pupilFill)
        }

        // armsUp 时顶部多一个小凸起
        if pose == .armsUp {
            fillRect(x: 5 + dx, y: 1 + dy, w: 4, h: 1.5, ctx: ctx, unit: unit, fill: topFill)
        }
    }

    private func fillRect(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat,
                          ctx: GraphicsContext, unit: CGFloat,
                          fill: GraphicsContext.Shading) {
        ctx.fill(Path(CGRect(x: x * unit, y: y * unit, width: w * unit, height: h * unit)), with: fill)
    }
}

/// 云朵精灵像素渲染器 —— viewBox 14×10 的 indigo 小云，带两只眼睛。
/// 动画：呼吸（上下浮动 ±1pt）+ 眨眼 + 走路时左右摇摆
public struct CloudView: View, PetSpriteView {
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
            CloudCanvasView(pose: pose, height: height, isWalking: isWalking, now: timeline.date.timeIntervalSinceReferenceDate)
        }
    }
}
