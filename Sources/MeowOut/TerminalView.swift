import SwiftUI

// Portions derived from HermesPet (https://github.com/basionwang-bot/HermesPet)
// Licensed under Apache 2.0 — see LICENSE.HermesPet
// Modifications: hardcoded colors, simplified animation, removed palette parameter

/// 提取出的独立绘制视图，支持通过外部传入 now（时间）和颜色覆盖（用于 Menu Bar 等场景）
public struct TerminalCanvasView: View {
    public let pose: ClawdPose
    public let height: CGFloat
    public var isWalking: Bool = false
    public var now: TimeInterval
    public var ledColorOverride: Color?
    public var flameOuterColorOverride: Color?
    public var bodyColorOverride: Color?
    
    private let isWorking: Bool = false

    // 不参与调色的默认色（保留 Codex 视觉特征）
    private static let bodyColor       = Color(red: 40.0/255,  green: 60.0/255,  blue: 100.0/255)
    private static let bodyTopColor    = Color(red: 60.0/255,  green: 90.0/255,  blue: 150.0/255)
    private static let bodyBottomColor = Color(red: 20.0/255,  green: 30.0/255,  blue: 50.0/255)
    private static let screenColor     = Color(red: 10.0/255,  green: 15.0/255,  blue: 31.0/255)   // #0A0F1F 头部黑屏
    private static let eyeWhiteColor   = Color(red: 240.0/255, green: 248.0/255, blue: 255.0/255)  // #F0F8FF 冷白眼
    private static let mouthColor      = Color(red: 168.0/255, green: 224.0/255, blue: 122.0/255)  // #A8E07A lime 嘴
    
    private static let defaultLedColor        = Color(red: 91.0/255,  green: 212.0/255, blue: 230.0/255)  // #5BD4E6 Codex cyan LED
    private static let defaultFlameInnerColor = Color(white: 1.0)                                          // 内焰纯白
    private static let defaultFlameMidColor   = Color(red: 91.0/255,  green: 212.0/255, blue: 230.0/255)  // cyan 中焰
    private static let defaultFlameOuterColor = Color(red: 255.0/255, green: 180.0/255, blue: 107.0/255)  // #FFB46B 外焰暖橙

    public static let viewBoxW: CGFloat = 14
    public static let viewBoxH: CGFloat = 10
    private static let centerX: CGFloat = 7
    private static let centerY: CGFloat = 5

    public init(pose: ClawdPose, height: CGFloat, isWalking: Bool = false, now: TimeInterval, ledColorOverride: Color? = nil, flameOuterColorOverride: Color? = nil, bodyColorOverride: Color? = nil) {
        self.pose = pose
        self.height = height
        self.isWalking = isWalking
        self.now = now
        self.ledColorOverride = ledColorOverride
        self.flameOuterColorOverride = flameOuterColorOverride
        self.bodyColorOverride = bodyColorOverride
    }

    public var body: some View {
        Canvas(rendersAsynchronously: false) { ctx, size in
            draw(ctx: ctx, size: size, now: now)
        }
        .frame(width: height * Self.viewBoxW / Self.viewBoxH, height: height)
    }

    private func draw(ctx: GraphicsContext, size: CGSize, now: TimeInterval) {
        let unit = min(size.width / Self.viewBoxW, size.height / Self.viewBoxH)
        
        let bodyFill        = GraphicsContext.Shading.color(bodyColorOverride ?? Self.bodyColor)
        let bodyTopFill     = GraphicsContext.Shading.color(Self.bodyTopColor)
        let bodyBottomFill  = GraphicsContext.Shading.color(Self.bodyBottomColor)
        let screenFill      = GraphicsContext.Shading.color(Self.screenColor)
        let eyeWhiteFill    = GraphicsContext.Shading.color(Self.eyeWhiteColor)
        let pupilFill       = GraphicsContext.Shading.color(Self.screenColor)
        let mouthFill       = GraphicsContext.Shading.color(Self.mouthColor)
        
        let flameOuterC = flameOuterColorOverride ?? Self.defaultFlameOuterColor
        let ledC = ledColorOverride ?? Self.defaultLedColor
        let flameMidC = ledColorOverride ?? Self.defaultFlameMidColor

        let flameInnerFill  = GraphicsContext.Shading.color(Self.defaultFlameInnerColor)
        let flameMidFill    = GraphicsContext.Shading.color(flameMidC)
        let flameOuterFill  = GraphicsContext.Shading.color(flameOuterC)
        let highlightFill   = GraphicsContext.Shading.color(.white.opacity(0.9))
        let shadowFill      = GraphicsContext.Shading.color(.black.opacity(0.35))
        let cyanLineFill    = GraphicsContext.Shading.color(ledC)

        // 呼吸 3.2s ±1.5%
        let breatheT = sin(now * 2 * .pi / 3.2)
        let sx: CGFloat = 1 + CGFloat(breatheT) * 0.015
        let sy: CGFloat = 1 - CGFloat(breatheT) * 0.015

        // 悬浮浮动 1.8s 周期 —— idle ±0.25 / walking ±0.5
        let hoverFreq = now * 2 * .pi / 1.8
        let hoverFloat: CGFloat = CGFloat(sin(hoverFreq)) * (isWalking ? 0.5 : 0.25)
        let dy = hoverFloat

        // 火焰脉冲
        let flameBaseLen: CGFloat = isWalking ? 1.9 : 1.0
        let flamePulse: CGFloat = CGFloat(sin(now * 18)) * 0.3
        let flameLen = max(0.6, flameBaseLen + flamePulse)
        let flameWNoise: CGFloat = CGFloat(sin(now * 22 + 1.5)) * 0.12

        // 眨眼
        let blinkPhase = (now / 5.0).truncatingRemainder(dividingBy: 1.0)
        let isBlinking = blinkPhase > 0.96
        let workBlinkPhase = (now / 1.8).truncatingRemainder(dividingBy: 1.0)
        let workBlinking = isWorking && (workBlinkPhase > 0.88 && workBlinkPhase < 0.94)
        let actualBlinking = isBlinking || workBlinking

        // 眼神偏移
        let (eyeShiftX, eyeShiftY): (CGFloat, CGFloat) = {
            switch pose {
            case .lookLeft:  return (-0.32, 0)
            case .lookRight: return ( 0.32, 0)
            case .armsUp:    return (0, -0.08)
            case .rest:
                return Self.continuousMouseEyeOffset()
            }
        }()

        let showSmile = (pose == .armsUp)

        // LED `</>` 颜色心跳
        let ledFreq = isWorking ? now * 4.0 : now * 0.8
        let ledPulse: Double = (sin(ledFreq * 2 * .pi) + 1) * 0.5
        let ledOpacity = 0.55 + ledPulse * 0.45
        let ledFill = GraphicsContext.Shading.color(ledC.opacity(ledOpacity))

        // 阴影
        let shadowW: CGFloat = isWalking ? 8.5 : 7
        let shadowH: CGFloat = isWalking ? 0.6 : 0.45
        let shadowRect = CGRect(
            x: (7 - shadowW / 2) * unit, y: 9.25 * unit,
            width: shadowW * unit, height: shadowH * unit
        )
        ctx.fill(Path(ellipseIn: shadowRect), with: shadowFill)

        // 双火焰
        let flameXs: [CGFloat] = [4.2, 8.8]
        for fx in flameXs {
            fillRect(x: fx - 0.45 + flameWNoise * 0.3, y: 6.5 + dy,
                     w: 1.5 + flameWNoise, h: flameLen,
                     ctx: ctx, unit: unit, sx: sx, sy: sy, fill: flameOuterFill)
            fillRect(x: fx - 0.2, y: 6.5 + dy,
                     w: 1.0, h: flameLen * 0.85,
                     ctx: ctx, unit: unit, sx: sx, sy: sy, fill: flameMidFill)
            fillRect(x: fx + 0.05, y: 6.5 + dy,
                     w: 0.5, h: flameLen * 0.55,
                     ctx: ctx, unit: unit, sx: sx, sy: sy, fill: flameInnerFill)
        }

        // 推进器口
        for fx in flameXs {
            fillRect(x: fx - 0.55, y: 5.95 + dy, w: 1.7, h: 0.65,
                     ctx: ctx, unit: unit, sx: sx, sy: sy, fill: bodyBottomFill)
            fillRect(x: fx - 0.45, y: 6.0 + dy, w: 1.5, h: 0.15,
                     ctx: ctx, unit: unit, sx: sx, sy: sy, fill: bodyFill)
        }

        // 手臂
        fillRect(x: 1.5, y: 4 + dy, w: 0.7, h: 1.5,
                 ctx: ctx, unit: unit, sx: sx, sy: sy, fill: bodyFill)
        fillRect(x: 11.8, y: 4 + dy, w: 0.7, h: 1.5,
                 ctx: ctx, unit: unit, sx: sx, sy: sy, fill: bodyFill)
        fillRect(x: 1.4, y: 5.3 + dy, w: 0.9, h: 0.4,
                 ctx: ctx, unit: unit, sx: sx, sy: sy, fill: bodyBottomFill)
        fillRect(x: 11.7, y: 5.3 + dy, w: 0.9, h: 0.4,
                 ctx: ctx, unit: unit, sx: sx, sy: sy, fill: bodyBottomFill)

        // 身体方块
        fillRect(x: 2.3, y: 3.5 + dy, w: 9.4, h: 2.5,
                 ctx: ctx, unit: unit, sx: sx, sy: sy, fill: bodyFill)
        fillRect(x: 2.6, y: 3.5 + dy, w: 8.8, h: 0.35,
                 ctx: ctx, unit: unit, sx: sx, sy: sy, fill: bodyTopFill)
        fillRect(x: 2.6, y: 5.65 + dy, w: 8.8, h: 0.35,
                 ctx: ctx, unit: unit, sx: sx, sy: sy, fill: bodyBottomFill)

        // 胸前 LED 框
        fillRect(x: 5.3, y: 4.0 + dy, w: 3.4, h: 1.6,
                 ctx: ctx, unit: unit, sx: sx, sy: sy, fill: screenFill)
        fillRect(x: 5.85, y: 4.3 + dy, w: 0.3, h: 0.4,
                 ctx: ctx, unit: unit, sx: sx, sy: sy, fill: ledFill)
        fillRect(x: 5.7, y: 4.6 + dy, w: 0.3, h: 0.35,
                 ctx: ctx, unit: unit, sx: sx, sy: sy, fill: ledFill)
        fillRect(x: 5.85, y: 4.85 + dy, w: 0.3, h: 0.4,
                 ctx: ctx, unit: unit, sx: sx, sy: sy, fill: ledFill)
        fillRect(x: 6.55, y: 4.95 + dy, w: 0.3, h: 0.35,
                 ctx: ctx, unit: unit, sx: sx, sy: sy, fill: ledFill)
        fillRect(x: 6.7, y: 4.65 + dy, w: 0.3, h: 0.35,
                 ctx: ctx, unit: unit, sx: sx, sy: sy, fill: ledFill)
        fillRect(x: 6.85, y: 4.3 + dy, w: 0.3, h: 0.35,
                 ctx: ctx, unit: unit, sx: sx, sy: sy, fill: ledFill)
        fillRect(x: 7.5, y: 4.3 + dy, w: 0.3, h: 0.4,
                 ctx: ctx, unit: unit, sx: sx, sy: sy, fill: ledFill)
        fillRect(x: 7.65, y: 4.6 + dy, w: 0.3, h: 0.35,
                 ctx: ctx, unit: unit, sx: sx, sy: sy, fill: ledFill)
        fillRect(x: 7.5, y: 4.85 + dy, w: 0.3, h: 0.4,
                 ctx: ctx, unit: unit, sx: sx, sy: sy, fill: ledFill)

        fillRect(x: 5.8, y: 3.0 + dy, w: 2.4, h: 0.6,
                 ctx: ctx, unit: unit, sx: sx, sy: sy, fill: bodyFill)

        fillRect(x: 3.5, y: 0.5 + dy, w: 7, h: 2.7,
                 ctx: ctx, unit: unit, sx: sx, sy: sy, fill: bodyFill)
        fillRect(x: 3.8, y: 0.5 + dy, w: 6.4, h: 0.35,
                 ctx: ctx, unit: unit, sx: sx, sy: sy, fill: bodyTopFill)
        fillRect(x: 3.8, y: 2.9 + dy, w: 6.4, h: 0.3,
                 ctx: ctx, unit: unit, sx: sx, sy: sy, fill: bodyBottomFill)

        fillRect(x: 4.0, y: 0.9 + dy, w: 6, h: 1.95,
                 ctx: ctx, unit: unit, sx: sx, sy: sy, fill: screenFill)

        let leftEyeCX: CGFloat = 5.3 + eyeShiftX
        let leftEyeCY: CGFloat = 1.55 + dy + eyeShiftY
        let rightEyeCX: CGFloat = 8.7 + eyeShiftX
        let rightEyeCY: CGFloat = 1.55 + dy + eyeShiftY

        if actualBlinking {
            fillRect(x: leftEyeCX - 0.4, y: leftEyeCY + 0.25, w: 0.8, h: 0.18,
                     ctx: ctx, unit: unit, sx: sx, sy: sy, fill: cyanLineFill)
            fillRect(x: rightEyeCX - 0.4, y: rightEyeCY + 0.25, w: 0.8, h: 0.18,
                     ctx: ctx, unit: unit, sx: sx, sy: sy, fill: cyanLineFill)
        } else {
            ctx.fill(Path(ellipseIn: ellipseRect(cx: leftEyeCX, cy: leftEyeCY, r: 0.55,
                                                 sx: sx, sy: sy, unit: unit)), with: eyeWhiteFill)
            ctx.fill(Path(ellipseIn: ellipseRect(cx: rightEyeCX, cy: rightEyeCY, r: 0.55,
                                                 sx: sx, sy: sy, unit: unit)), with: eyeWhiteFill)
            ctx.fill(Path(ellipseIn: ellipseRect(cx: leftEyeCX, cy: leftEyeCY + 0.05, r: 0.27,
                                                 sx: sx, sy: sy, unit: unit)), with: pupilFill)
            ctx.fill(Path(ellipseIn: ellipseRect(cx: rightEyeCX, cy: rightEyeCY + 0.05, r: 0.27,
                                                 sx: sx, sy: sy, unit: unit)), with: pupilFill)
            ctx.fill(Path(ellipseIn: ellipseRect(cx: leftEyeCX - 0.15, cy: leftEyeCY - 0.08, r: 0.12,
                                                 sx: sx, sy: sy, unit: unit)), with: highlightFill)
            ctx.fill(Path(ellipseIn: ellipseRect(cx: rightEyeCX - 0.15, cy: rightEyeCY - 0.08, r: 0.12,
                                                 sx: sx, sy: sy, unit: unit)), with: highlightFill)
        }

        if showSmile {
            fillRect(x: 5.8, y: 2.5 + dy, w: 0.5, h: 0.2,
                     ctx: ctx, unit: unit, sx: sx, sy: sy, fill: mouthFill)
            fillRect(x: 6.3, y: 2.62 + dy, w: 1.4, h: 0.22,
                     ctx: ctx, unit: unit, sx: sx, sy: sy, fill: mouthFill)
            fillRect(x: 7.7, y: 2.5 + dy, w: 0.5, h: 0.2,
                     ctx: ctx, unit: unit, sx: sx, sy: sy, fill: mouthFill)
        } else {
            let baseMouthY: CGFloat = 2.55 + dy
            let leftMouthY: CGFloat = (pose == .lookRight) ? baseMouthY - 0.08 : baseMouthY
            let rightMouthY: CGFloat = (pose == .lookLeft) ? baseMouthY - 0.08 : baseMouthY
            fillRect(x: 5.8, y: leftMouthY, w: 1.2, h: 0.2,
                     ctx: ctx, unit: unit, sx: sx, sy: sy, fill: mouthFill)
            fillRect(x: 7.0, y: rightMouthY, w: 1.2, h: 0.2,
                     ctx: ctx, unit: unit, sx: sx, sy: sy, fill: mouthFill)
        }
    }

    private func ellipseRect(cx: CGFloat, cy: CGFloat, r: CGFloat,
                             sx: CGFloat, sy: CGFloat, unit: CGFloat) -> CGRect {
        let screenCX = (cx - Self.centerX) * sx * unit + Self.centerX * unit
        let screenCY = (cy - Self.centerY) * sy * unit + Self.centerY * unit
        let screenR = r * sx * unit
        return CGRect(x: screenCX - screenR, y: screenCY - screenR,
                      width: screenR * 2, height: screenR * 2)
    }

    private static func continuousMouseEyeOffset() -> (CGFloat, CGFloat) {
        let loc = NSEvent.mouseLocation
        let screen = NSScreen.main
        guard let screen, screen.frame.contains(loc) else { return (0, 0) }
        let halfW = screen.frame.width / 2
        let halfH = screen.frame.height / 2
        let nx = max(-1, min(1, (loc.x - screen.frame.midX) / halfW))
        let ny = max(-1, min(1, (loc.y - screen.frame.midY) / halfH))
        return (CGFloat(nx) * 0.3, CGFloat(-ny) * 0.15)
    }

    private func fillRect(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat,
                          ctx: GraphicsContext, unit: CGFloat,
                          sx: CGFloat = 1, sy: CGFloat = 1,
                          fill: GraphicsContext.Shading) {
        let screenX = (x - Self.centerX) * sx * unit + Self.centerX * unit
        let screenY = (y - Self.centerY) * sy * unit + Self.centerY * unit
        let screenW = w * sx * unit
        let screenH = h * sy * unit
        ctx.fill(Path(CGRect(x: screenX, y: screenY, width: screenW, height: screenH)), with: fill)
    }
}

/// 钢铁侠风格小方块机器人 —— viewBox 14×10
public struct TerminalView: View, PetSpriteView {
    public let pose: ClawdPose
    public let height: CGFloat
    /// 是否"走路"中 —— 实际是飞行加速：火焰拉长 + 浮动幅度加大
    public var isWalking: Bool = false

    public init(pose: ClawdPose, height: CGFloat, isWalking: Bool = false) {
        self.pose = pose
        self.height = height
        self.isWalking = isWalking
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0/60.0)) { timeline in
            TerminalCanvasView(pose: pose, height: height, isWalking: isWalking, now: timeline.date.timeIntervalSinceReferenceDate)
        }
    }
}
