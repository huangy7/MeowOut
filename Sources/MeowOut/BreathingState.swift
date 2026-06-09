import Foundation
import Observation
import SwiftUI

public enum BreathingPhase: String {
    case inhale
    case holdAfterInhale
    case exhale
    case holdAfterExhale
    
    public var displayName: String {
        switch self {
        case .inhale: return "吸气"
        case .holdAfterInhale, .holdAfterExhale: return "屏气"
        case .exhale: return "呼气"
        }
    }
}

public struct BreathingPattern: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let inhaleDuration: Int
    public let holdAfterInhaleDuration: Int
    public let exhaleDuration: Int
    public let holdAfterExhaleDuration: Int
    
    public static let box = BreathingPattern(id: "box", name: "箱式呼吸 (Box)", inhaleDuration: 4, holdAfterInhaleDuration: 4, exhaleDuration: 4, holdAfterExhaleDuration: 4)
    public static let relax = BreathingPattern(id: "478", name: "4-7-8 放松", inhaleDuration: 4, holdAfterInhaleDuration: 7, exhaleDuration: 8, holdAfterExhaleDuration: 0)
    public static let diaphragmatic = BreathingPattern(id: "diaphragmatic", name: "腹式呼吸", inhaleDuration: 4, holdAfterInhaleDuration: 0, exhaleDuration: 6, holdAfterExhaleDuration: 0)
    
    public static let all: [BreathingPattern] = [.box, .relax, .diaphragmatic]
}

@Observable
@MainActor
public final class BreathingState {
    public var currentPattern: BreathingPattern = .box
    public var currentPhase: BreathingPhase = .inhale
    public var secondsRemaining: Int = 4
    public var isRunning: Bool = false
    
    public var totalSessionSeconds: Int = 300 // 5 minutes
    public var sessionSecondsRemaining: Int = 300
    
    private var timerTask: Task<Void, Never>?
    
    public init() {}
    
    public func start() {
        stop()
        isRunning = true
        currentPhase = .inhale
        secondsRemaining = currentPattern.inhaleDuration
        sessionSecondsRemaining = totalSessionSeconds
        
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { break }
                self?.tick()
            }
        }
    }
    
    public func stop() {
        isRunning = false
        timerTask?.cancel()
        timerTask = nil
        currentPhase = .inhale
        secondsRemaining = currentPattern.inhaleDuration
        sessionSecondsRemaining = totalSessionSeconds
    }
    
    public func setPattern(_ pattern: BreathingPattern) {
        currentPattern = pattern
        if !isRunning {
            secondsRemaining = pattern.inhaleDuration
        }
    }
    
    private func tick() {
        sessionSecondsRemaining -= 1
        if sessionSecondsRemaining <= 0 {
            stop()
            return
        }
        
        if secondsRemaining > 1 {
            secondsRemaining -= 1
        } else {
            advancePhase()
        }
    }
    
    private func advancePhase() {
        switch currentPhase {
        case .inhale:
            if currentPattern.holdAfterInhaleDuration > 0 {
                currentPhase = .holdAfterInhale
                secondsRemaining = currentPattern.holdAfterInhaleDuration
            } else {
                currentPhase = .exhale
                secondsRemaining = currentPattern.exhaleDuration
            }
        case .holdAfterInhale:
            currentPhase = .exhale
            secondsRemaining = currentPattern.exhaleDuration
        case .exhale:
            if currentPattern.holdAfterExhaleDuration > 0 {
                currentPhase = .holdAfterExhale
                secondsRemaining = currentPattern.holdAfterExhaleDuration
            } else {
                currentPhase = .inhale
                secondsRemaining = currentPattern.inhaleDuration
            }
        case .holdAfterExhale:
            currentPhase = .inhale
            secondsRemaining = currentPattern.inhaleDuration
        }
    }
}
