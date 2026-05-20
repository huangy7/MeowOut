import SwiftUI
import Observation

/// 管理桌宠的实时表现状态
@Observable
@MainActor
public final class PetState {
    public var position: CGPoint = CGPoint(x: 200, y: 200)
    public var facingRight: Bool = true
    public var pose: ClawdPose = .rest
    public var isWalking: Bool = false
    public var bubbleText: String = ""
    public var bubbleVisible: Bool = false
    public var showBreathingButton: Bool = false
    public var isBeingDragged: Bool = false

    /// 标记气泡是否被锁定（用于显示高优先级交互对话，防止被自动倒计时覆盖）
    public var isBubbleLocked: Bool = false

    /// 用户点击气泡的次数（用于多段逃逸逻辑）
    public var tapCount: Int = 0

    /// 标记是否正在执行逃离动画
    public var isEscaping: Bool = false

    /// 气泡是否显示喝水 +1 按钮
    public var showWaterButton: Bool = false

    private var lockTask: Task<Void, Never>?

    public init() {}

    /// 显示一个带锁定的气泡，防止被自动轮播覆盖
    public func showLockedBubble(_ text: String, duration: TimeInterval = 3.0) {
        // 取消已有任务，防止重复触发解锁逻辑
        lockTask?.cancel()

        self.bubbleText = text
        self.bubbleVisible = true
        self.isBubbleLocked = true

        // 开启跳动动画反馈
        self.pose = .armsUp

        lockTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            if !Task.isCancelled {
                self.isBubbleLocked = false
                self.tapCount = 0
                self.pose = .rest
            }
        }
    }
}
