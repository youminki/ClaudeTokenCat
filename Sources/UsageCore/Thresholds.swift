import Foundation

/// 고양이 상태 (§F2 5단계 상태 머신).
public enum CatState: String, CaseIterable, Sendable {
    case sleeping   // 😴 0 tok/min, 5분 이상 무활동
    case walking    // 🚶 1 ~ 2,000
    case running    // 🏃 2,000 ~ 10,000
    case dashing    // 💨 10,000 ~ 30,000
    case rainbow    // 🌈 30,000+

    /// 프레임 간격 (§F2 표).
    public var frameInterval: TimeInterval {
        switch self {
        case .sleeping: return 1.000
        case .walking:  return 0.200
        case .running:  return 0.100
        case .dashing:  return 0.060
        case .rainbow:  return 0.040
        }
    }

    public var emoji: String {
        switch self {
        case .sleeping: return "😴"
        case .walking:  return "🚶"
        case .running:  return "🏃"
        case .dashing:  return "💨"
        case .rainbow:  return "🌈"
        }
    }

    public var label: String {
        switch self {
        case .sleeping: return "잠자기"
        case .walking:  return "산책"
        case .running:  return "달리기"
        case .dashing:  return "질주"
        case .rainbow:  return "무지개 모드"
        }
    }
}

public struct Thresholds: Sendable {
    /// tokens/min 경계값. 민감도 조절 시 이 값들에 배율을 곱한다.
    public var walk: Double = 1
    public var run: Double = 2_000
    public var dash: Double = 10_000
    public var rainbow: Double = 30_000

    /// 무활동 → 잠자기 전환 시간 (5분).
    public var sleepAfterIdle: TimeInterval = 5 * 60

    public init() {}

    /// 민감도 프리셋 (낮음/보통/높음). 높음 = 적은 토큰으로도 빨리 뛴다.
    public static func preset(sensitivity: Sensitivity) -> Thresholds {
        var t = Thresholds()
        let m = sensitivity.multiplier
        t.run *= m
        t.dash *= m
        t.rainbow *= m
        return t
    }

    public enum Sensitivity: String, CaseIterable, Sendable {
        case low, normal, high
        var multiplier: Double {
            switch self {
            case .low: return 2.0
            case .normal: return 1.0
            case .high: return 0.5
            }
        }
    }

    /// burn rate와 마지막 활동 이후 경과 시간으로 상태 결정.
    public func state(burnRate: Double, idleSeconds: TimeInterval) -> CatState {
        if burnRate < walk {
            return idleSeconds >= sleepAfterIdle ? .sleeping : .walking
        }
        if idleSeconds >= sleepAfterIdle { return .sleeping }
        switch burnRate {
        case ..<run: return .walking
        case ..<dash: return .running
        case ..<rainbow: return .dashing
        default: return .rainbow
        }
    }
}
