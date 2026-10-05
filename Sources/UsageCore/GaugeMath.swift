import Foundation

/// 게이지 하나(세션 또는 주간)의 표시값.
public struct GaugeReading: Equatable, Sendable {
    public let percent: Double
    /// 마지막 공식 조회값. nil이면 추정 한도로 계산한 값이다.
    public let officialBase: Double?

    public init(percent: Double, officialBase: Double?) {
        self.percent = percent
        self.officialBase = officialBase
    }

    public var isOfficial: Bool { officialBase != nil }

    /// 공식 조회 이후 로컬 소모분이 얹혀 있는지.
    public var isInterpolating: Bool {
        officialBase.map { percent > $0 + 0.05 } ?? false
    }
}

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

    /// 공식 %가 있으면 보간값, 없으면 추정 한도 대비 비율. 엔진과 팝오버가 같은 값을 쓰도록 한곳에서 계산한다.
    public static func reading(officialBase: Double?, windowTokens: Int, tokensSince: Int,
                               estimatedLimit: Int) -> GaugeReading {
        if let base = officialBase {
            return GaugeReading(percent: interpolated(base: base, windowTokens: windowTokens,
                                                      tokensSince: tokensSince),
                                officialBase: base)
        }
        let percent = estimatedLimit > 0 ? Double(windowTokens) / Double(estimatedLimit) * 100 : 0
        return GaugeReading(percent: percent, officialBase: nil)
    }

    /// 공식 %로 역산한 창 전체 한도(로컬 토큰 단위). 추정 모드 자동 보정에 쓴다.
    public static func impliedLimit(base: Double, windowTokens: Int, tokensSince: Int) -> Int? {
        tokensPerPercent(base: base, windowTokens: windowTokens, tokensSince: tokensSince)
            .map { Int($0 * 100) }
    }

    /// 현재 속도로 남은 토큰을 다 쓰는 데 걸리는 분. 속도가 없거나 남은 양이 없으면 nil.
    public static func minutesUntilFull(remainingTokens: Int?, burnRate: Double) -> Int? {
        guard let remaining = remainingTokens, remaining > 0, burnRate >= 1 else { return nil }
        return Int(Double(remaining) / burnRate)
    }
}
