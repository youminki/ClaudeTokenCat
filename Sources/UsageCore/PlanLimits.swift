import Foundation

/// 플랜 프리셋 (§5 — 폴백 전용, 공식 연동 실패 시에만 게이지에 사용).
/// 모든 값은 커뮤니티 추정치 — UI에서 "(추정)" 라벨 필수.
public enum Plan: String, CaseIterable, Sendable {
    case pro, max5x, max20x, custom

    public var displayName: String {
        switch self {
        case .pro: return "Pro"
        case .max5x: return "Max 5x"
        case .max20x: return "Max 20x"
        case .custom: return "Custom"
        }
    }

    /// session_tokens_est (§5). custom은 nil → 사용자 입력값 사용.
    public var sessionTokensEst: Int? {
        switch self {
        case .pro: return 500_000
        case .max5x: return 2_500_000
        case .max20x: return 10_000_000
        case .custom: return nil
        }
    }

    public static let weeklyMultiplierEst = 8
}

public enum PlanLimits {

    /// 추정 세션 한도 결정. 우선순위: 캘리브레이션 > custom 입력 > 플랜 프리셋.
    public static func sessionLimit(plan: Plan, customLimit: Int?, calibratedLimit: Int?) -> Int {
        if let calibrated = calibratedLimit, calibrated > 0 { return calibrated }
        if plan == .custom, let custom = customLimit, custom > 0 { return custom }
        return plan.sessionTokensEst ?? 500_000
    }

    /// 추정 주간 한도. 우선순위: 주간 캘리브레이션 > 세션 한도 × 8.
    public static func weeklyLimit(sessionLimit: Int, calibratedLimit: Int? = nil) -> Int {
        if let calibrated = calibratedLimit, calibrated > 0 { return calibrated }
        return sessionLimit * Plan.weeklyMultiplierEst
    }

    /// `/usage` 실측 %로 한도 역산 (§F5 캘리브레이션). 세션·주간 공용.
    /// 예: 현재 창 토큰 1.2M인데 /usage가 60%라면 → 한도 2M.
    public static func calibratedLimit(windowTokens: Int, usagePercent: Double) -> Int? {
        guard windowTokens > 0, usagePercent > 0, usagePercent <= 100 else { return nil }
        return Int(Double(windowTokens) / (usagePercent / 100))
    }
}
