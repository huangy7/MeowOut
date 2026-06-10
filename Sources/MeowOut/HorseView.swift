import SwiftUI

// Portions derived from HermesPet (https://github.com/basionwang-bot/HermesPet)
// Licensed under Apache 2.0 — see LICENSE.HermesPet
// Modifications: hardcoded colors, simplified animation, removed palette parameter

public struct HorseCanvasView: View {
    public let pose: ClawdPose
    public let height: CGFloat
    public var isWalking: Bool = false
    public var now: TimeInterval

    private static let bodyColor       = Color(red: 255.0/255, green: 204.0/255, blue: 0.0/255)    // 金黄
    private static let bodyTopColor    = Color(red: 255.0/255, green: 220.0/255, blue: 50.0/255)
    private static let bodyBottomColor = Color(red: 220.0/255, green: 170.0/255, blue: 0.0/255)
    private static let maneColor       = Color(red: 217.0/255, green: 178.0/255, blue: 102.0/255)  // #D9B266 深 amber 金
    private static let hoofColor       = Color(red: 91.0/255,  green: 58.0/255,  blue: 31.0/255)   // #5B3A1F 蹄子深棕
    private static let wingColor       = Color(red: 255.0/255, green: 250.0/255, blue: 229.0/255)  // #FFFAE5 奶油白
    private static let wingShadowColor = Color(red: 230.0/255, green: 215.0/255, blue: 170.0/255)  // #E6D7AA 翼根阴影 / 羽缝

    public static let viewBoxW: CGFloat = 14
    public static let viewBoxH: CGFloat = 10
    private static let centerX: CGFloat = 7
    private static let centerY: CGFloat = 5

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
        
        let bodyFill       = GraphicsContext.Shading.color(Self.bodyColor)
        let bodyTopFill    = GraphicsContext.Shading.color(Self.bodyTopColor)
        let bodyBottomFill = GraphicsContext.Shading.color(Self.bodyBottomColor)
        let maneFill       = GraphicsContext.Shading.color(Self.maneColor)
        let hoofFill       = GraphicsContext.Shading.color(Self.hoofColor)
        let wingFill       = GraphicsContext.Shading.color(Self.wingColor)
        let wingShadowFill = GraphicsContext.Shading.color(Self.wingShadowColor)
        let eyeFill        = GraphicsContext.Shading.color(.black)
        let highlightFill  = GraphicsContext.Shading.color(.white)
        let shadowFill     = GraphicsContext.Shading.color(.black.opacity(0.4))

        // 呼吸
        let breatheT = sin(now * 2 * .pi / 2.5)
        let sx: CGFloat = 1 + CGFloat(breatheT) * 0.03
        let sy: CGFloat = 1 - CGFloat(breatheT) * 0.05

        // 走路 phase 0~1
        let walkPhase = isWalking ? (now / 0.8).truncatingRemainder(dividingBy: 1.0) : 0

        // 眨眼
        let blinkPhase = (now / 5.0).truncatingRemainder(dividingBy: 1.0)
        let isBlinking = blinkPhase > 0.96

        // 抬头
        let headRaise: CGFloat = (pose == .armsUp) ? -1.2 : 0

        // 眼神
        let eyeShiftX: CGFloat = {
            switch pose {
            case .lookLeft:  return -0.4
            case .lookRight: return  0.4
            case .armsUp, .rest: return 0
            }
        }()

        // 身体上下 bob
        let bodyBob: CGFloat = isWalking ? CGFloat(sin(walkPhase * 2 * .pi * 2)) * 0.3 : 0

        // 鬃毛 / 尾巴 / 翅膀飘动
        let maneFreq = isWalking ? walkPhase * 2 * .pi * 2 : now * 1.2
        let maneFloat: CGFloat = CGFloat(sin(maneFreq)) * (isWalking ? 0.55 : 0.22)
        let maneFloatLag: CGFloat = CGFloat(sin(maneFreq - 0.6)) * (isWalking ? 0.7 : 0.3)
        let tailWaveX: CGFloat = CGFloat(sin(maneFreq * 0.8)) * (isWalking ? 0.45 : 0.22)
        let tailWaveY: CGFloat = CGFloat(cos(maneFreq * 0.8)) * (isWalking ? 0.35 : 0.18)
        let wingFlap: CGFloat = CGFloat(sin(maneFreq * 1.4)) * (isWalking ? 0.5 : 0.18)

        let idleBobY: CGFloat = isWalking ? 0 : CGFloat(breatheT) * 0.35
        let dy = bodyBob + idleBobY

        // 阴影
        let shadowRect = CGRect(
            x: 2.5 * unit, y: 9.2 * unit,
            width: 7 * unit, height: 0.55 * unit
        )
        ctx.fill(Path(ellipseIn: shadowRect), with: shadowFill)

        // 4 条腿
        let legXs: [CGFloat] = [3, 4, 6.8, 7.8]
        let legGroups: [Int] = [0, 1, 1, 0]
        for (idx, x) in legXs.enumerated() {
            let liftY = legLiftOffset(group: legGroups[idx], phase: walkPhase)
            fillRect(x: x, y: 7 + dy + liftY, w: 1, h: 1.7, ctx: ctx, unit: unit, sx: sx, sy: sy, fill: bodyFill)
            fillRect(x: x, y: 8.55 + dy + liftY, w: 1, h: 0.4, ctx: ctx, unit: unit, sx: sx, sy: sy, fill: hoofFill)
        }

        // 尾巴
        fillRect(x: 1.5 + tailWaveX * 0.4, y: 4.2 + dy, w: 0.7, h: 1.4, ctx: ctx, unit: unit, sx: sx, sy: sy, fill: maneFill)
        fillRect(x: 0.8 + tailWaveX * 0.9, y: 5.2 + dy + tailWaveY * 0.5, w: 1, h: 1.6, ctx: ctx, unit: unit, sx: sx, sy: sy, fill: maneFill)
        fillRect(x: 0.3 + tailWaveX * 1.4, y: 6.4 + dy + tailWaveY, w: 0.8, h: 1.2, ctx: ctx, unit: unit, sx: sx, sy: sy, fill: maneFill)

        // 躯干
        fillRect(x: 2, y: 4 + dy, w: 7, h: 2.6, ctx: ctx, unit: unit, sx: sx, sy: sy, fill: bodyFill)
        fillRect(x: 2.3, y: 4 + dy, w: 6.4, h: 0.4, ctx: ctx, unit: unit, sx: sx, sy: sy, fill: bodyTopFill)
        fillRect(x: 2.3, y: 6.2 + dy, w: 6.4, h: 0.4, ctx: ctx, unit: unit, sx: sx, sy: sy, fill: bodyBottomFill)

        // 鬃毛
        fillRect(x: 4.5 + maneFloatLag * 0.6, y: 3.4 + dy + maneFloatLag * 0.8, w: 2.6, h: 0.9, ctx: ctx, unit: unit, sx: sx, sy: sy, fill: maneFill)
        fillRect(x: 3.2 + maneFloatLag * 1.0, y: 3.7 + dy + maneFloatLag * 1.3, w: 1.6, h: 0.7, ctx: ctx, unit: unit, sx: sx, sy: sy, fill: maneFill)

        // 翅膀
        fillRect(x: 4.8, y: 3.4 + dy + wingFlap * 0.2, w: 2.2, h: 1.0, ctx: ctx, unit: unit, sx: sx, sy: sy, fill: wingFill)
        fillRect(x: 4.8, y: 4.2 + dy + wingFlap * 0.2, w: 2.2, h: 0.2, ctx: ctx, unit: unit, sx: sx, sy: sy, fill: wingShadowFill)
        fillRect(x: 3.8 + wingFlap * 0.3, y: 2.7 + dy + wingFlap * 0.6, w: 2.0, h: 0.9, ctx: ctx, unit: unit, sx: sx, sy: sy, fill: wingFill)
        fillRect(x: 4.5 + wingFlap * 0.3, y: 3.0 + dy + wingFlap * 0.6, w: 0.25, h: 0.4, ctx: ctx, unit: unit, sx: sx, sy: sy, fill: wingShadowFill)
        fillRect(x: 2.9 + wingFlap * 0.6, y: 2.3 + dy + wingFlap * 1.1, w: 1.6, h: 0.8, ctx: ctx, unit: unit, sx: sx, sy: sy, fill: wingFill)
        fillRect(x: 2.9 + wingFlap * 0.6, y: 2.9 + dy + wingFlap * 1.1, w: 1.6, h: 0.2, ctx: ctx, unit: unit, sx: sx, sy: sy, fill: wingShadowFill)

        // 颈
        let neckTopY: CGFloat = 3 + headRaise
        let neckBottomY: CGFloat = 4.4
        let neckH: CGFloat = neckBottomY - neckTopY
        fillRect(x: 6.5, y: neckTopY + dy, w: 1.8, h: neckH, ctx: ctx, unit: unit, sx: sx, sy: sy, fill: bodyFill)

        // 鬃毛 3
        fillRect(x: 6.4 + maneFloat * 0.3, y: 2.5 + dy + headRaise + maneFloat * 0.7, w: 1.8, h: 1.1, ctx: ctx, unit: unit, sx: sx, sy: sy, fill: maneFill)

        // 头
        fillRect(x: 8, y: 2 + dy + headRaise, w: 2.5, h: 2.5, ctx: ctx, unit: unit, sx: sx, sy: sy, fill: bodyFill)
        fillRect(x: 10.4, y: 3.6 + dy + headRaise, w: 1.0, h: 0.7, ctx: ctx, unit: unit, sx: sx, sy: sy, fill: bodyFill)
        fillRect(x: 10.4, y: 4.15 + dy + headRaise, w: 1.0, h: 0.18, ctx: ctx, unit: unit, sx: sx, sy: sy, fill: bodyBottomFill)
        fillRect(x: 11.0, y: 3.85 + dy + headRaise, w: 0.35, h: 0.3, ctx: ctx, unit: unit, sx: sx, sy: sy, fill: hoofFill)

        // 鬃毛 4
        fillRect(x: 7.5 + maneFloat * 0.4, y: 1.4 + dy + headRaise + maneFloat * 1.2, w: 1.5, h: 1.0, ctx: ctx, unit: unit, sx: sx, sy: sy, fill: maneFill)

        // 耳朵
        fillRect(x: 9, y: 0.7 + dy + headRaise, w: 0.6, h: 1.3, ctx: ctx, unit: unit, sx: sx, sy: sy, fill: bodyFill)
        fillRect(x: 9.7, y: 0.7 + dy + headRaise, w: 0.6, h: 1.3, ctx: ctx, unit: unit, sx: sx, sy: sy, fill: bodyFill)

        // 眼睛
        let eyeX: CGFloat = 9.5 + eyeShiftX
        let eyeY: CGFloat = 2.7 + dy + headRaise
        if isBlinking {
            fillRect(x: eyeX, y: eyeY + 0.35, w: 0.6, h: 0.2, ctx: ctx, unit: unit, sx: sx, sy: sy, fill: eyeFill)
        } else {
            fillRect(x: eyeX, y: eyeY, w: 0.6, h: 0.6, ctx: ctx, unit: unit, sx: sx, sy: sy, fill: eyeFill)
            fillRect(x: eyeX + 0.05, y: eyeY + 0.08, w: 0.22, h: 0.22, ctx: ctx, unit: unit, sx: sx, sy: sy, fill: highlightFill)
        }
    }

    private func legLiftOffset(group: Int, phase: Double) -> CGFloat {
        guard isWalking else { return 0 }
        let p = phase
        let groupPhase = (group == 0) ? p : (p + 0.5).truncatingRemainder(dividingBy: 1.0)
        if groupPhase < 0.5 {
            return CGFloat(-sin(groupPhase * 2 * .pi)) * 0.8
        }
        return 0
    }

    private func fillRect(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat,
                          ctx: GraphicsContext, unit: CGFloat,
                          sx: CGFloat, sy: CGFloat,
                          fill: GraphicsContext.Shading) {
        let screenX = (x - Self.centerX) * sx * unit + Self.centerX * unit
        let screenY = (y - Self.centerY) * sy * unit + Self.centerY * unit
        let screenW = w * sx * unit
        let screenH = h * sy * unit
        ctx.fill(Path(CGRect(x: screenX, y: screenY, width: screenW, height: screenH)), with: fill)
    }
}

/// 金黄像素小马渲染器 —— viewBox 14×10
/// 动画：呼吸 (±3% x / ±5% y) + 眨眼 + 走路 trot 步态 + 鬃毛/尾巴飘动 + 翅膀扑扇
public struct HorseView: View, PetSpriteView {
    public let pose: ClawdPose
    /// 精灵高度。最终 frame 宽 = height × 1.4（viewBox 14:10）
    public let height: CGFloat
    /// 是否在走路 —— 控制 trot 步态 + 鬃毛/尾巴飘动幅度
    public var isWalking: Bool = false

    public init(pose: ClawdPose, height: CGFloat, isWalking: Bool = false) {
        self.pose = pose
        self.height = height
        self.isWalking = isWalking
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0/60.0)) { timeline in
            HorseCanvasView(pose: pose, height: height, isWalking: isWalking, now: timeline.date.timeIntervalSinceReferenceDate)
        }
    }
}
