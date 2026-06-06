import Foundation

public struct LauncherTriggerStateMachine {
    public struct Configuration {
        public let doubleClickToActivate: Bool
        public let clickToLaunch: Bool
        public let longPressDelay: TimeInterval
        public let doubleClickInterval: TimeInterval

        public init(
            doubleClickToActivate: Bool,
            clickToLaunch: Bool,
            longPressDelay: TimeInterval,
            doubleClickInterval: TimeInterval
        ) {
            self.doubleClickToActivate = doubleClickToActivate
            self.clickToLaunch = clickToLaunch
            self.longPressDelay = longPressDelay
            self.doubleClickInterval = doubleClickInterval
        }
    }

    public enum Action: Equatable {
        case show
        case toggle
        case triggerHoveredAndClose
    }

    private var isPressed = false
    private var isHoldActivated = false
    private var lastReleaseTime: TimeInterval?
    private var currentPressStartTime: TimeInterval?
    private var currentPressCanLongPress = true
    private var suppressCurrentRelease = false

    public init() {}

    public mutating func reset() {
        isPressed = false
        isHoldActivated = false
        lastReleaseTime = nil
        currentPressStartTime = nil
        currentPressCanLongPress = true
        suppressCurrentRelease = false
    }

    public mutating func keyDown(at time: TimeInterval, config: Configuration) -> [Action] {
        guard !isPressed else { return [] }

        isPressed = true
        isHoldActivated = false
        currentPressStartTime = time
        currentPressCanLongPress = !config.doubleClickToActivate
        suppressCurrentRelease = false

        guard config.doubleClickToActivate else {
            return []
        }

        if let lastReleaseTime, time.timeIntervalSince(lastReleaseTime) <= config.doubleClickInterval {
            self.lastReleaseTime = nil
            currentPressCanLongPress = true
        }

        return []
    }

    public mutating func longPressTimerFired(at time: TimeInterval, config: Configuration) -> [Action] {
        guard isPressed, !isHoldActivated, let currentPressStartTime else { return [] }
        guard currentPressCanLongPress else { return [] }
        guard time.timeIntervalSince(currentPressStartTime) + 0.000_001 >= config.longPressDelay else { return [] }

        isHoldActivated = true
        lastReleaseTime = nil
        suppressCurrentRelease = true
        return [.show]
    }

    public mutating func keyUp(at time: TimeInterval, config: Configuration) -> [Action] {
        guard isPressed else { return [] }

        isPressed = false
        currentPressStartTime = nil

        if isHoldActivated {
            isHoldActivated = false
            return config.clickToLaunch ? [] : [.triggerHoveredAndClose]
        }

        if suppressCurrentRelease {
            suppressCurrentRelease = false
            return []
        }

        if config.doubleClickToActivate {
            lastReleaseTime = time
            currentPressCanLongPress = false
            return []
        }

        return [.toggle]
    }
}

private extension TimeInterval {
    func timeIntervalSince(_ earlier: TimeInterval) -> TimeInterval {
        self - earlier
    }
}
