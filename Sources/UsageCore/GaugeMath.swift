import Foundation

/// 보간 게이지 계산 (§F3 갱신 전략).
///
/// 공식 %에 얹을 보간분을 플랜 추정 한도로 환산하면 안 된다 — JSONL 토큰은
/// 캐시 리드가 대부분이라 실제 한도 소진보다 수십 배 커서 게이지가 몇 분 만에
/// 100%로 폭주한다(오탐 빨간 고양이·경고 알림). 대신 **공식 1%당 로컬 토큰 수를
/// 실측으로 역산**한다: 조회 시점의 창 토큰 ÷ 공식 %.
public enum GaugeMath {

    /// 역산이 불안정해지는 하한 — 공식 %가 이보다 작으면 보간하지 않는다.
    public static let minimumBaseForCalibration: Double = 5

    /// 공식 1%에 해당하는 로컬 토큰 수. 데이터 부족 시 nil (보간 생략).
    /// - windowTokens: 현재 창의 로컬 토큰 합계 (조회 이후 소모분 포함)
    /// - tokensSince: 마지막 공식 조회 이후 소모분
    public static func tokensPerPercent(base: Double, windowTokens: Int, tokensSince: Int) -> Double? {
        let tokensAtFetch = windowTokens - tokensSince
        guard base >= minimumBaseForCalibration, tokensAtFetch > 0 else { return nil }
        return Double(tokensAtFetch) / base
    }

    /// 공식 % + 로컬 보간분 (0~100 클램프).
    public static func interpolated(base: Double, windowTokens: Int, tokensSince: Int) -> Double {
        let clamped = min(max(base, 0), 100)
        guard tokensSince > 0,
              let perPercent = tokensPerPercent(base: base, windowTokens: windowTokens,
                                                tokensSince: tokensSince)
        else { return clamped }
        return min(clamped + Double(tokensSince) / perPercent, 100)
    }

    /// 남은 토큰 추정 (알림의 "약 N분 분량 남음" 계산용). 역산 불가 시 nil.
    public static func remainingTokens(base: Double, windowTokens: Int, tokensSince: Int) -> Int? {
        guard let perPercent = tokensPerPercent(base: base, windowTokens: windowTokens,
                                                tokensSince: tokensSince) else { return nil }
        let pct = interpolated(base: base, windowTokens: windowTokens, tokensSince: tokensSince)
        return Int((100 - pct) * perPercent)
    }
}
