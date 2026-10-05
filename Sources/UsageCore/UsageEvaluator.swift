import Foundation

/// 틱 한 번의 판단: 공식 값을 쓸 수 있는지, 게이지 %, 한도 단계.
/// 엔진의 큐·타이머와 떼어 두어 단위 테스트한다.
public enum UsageEvaluator {

    public struct Result: Equatable, Sendable {
        public let session: GaugeReading
        public let weekly: GaugeReading
        /// 현재 속도로 세션 한도에 닿기까지 남은 분. 속도가 없으면 nil.
        public let sessionMinutesLeft: Int?
        /// 알림·고양이 오버라이드를 평가해도 되는지.
        public let authoritative: Bool
        public let level: UsageAlertLevel
    }

    /// 연동이 켜져 있고 유예 시간 안에 받은 공식 값만 쓴다.
    public static func usableOfficial(_ official: OfficialUsage?, enabled: Bool, now: Date,
                                      grace: TimeInterval) -> OfficialUsage? {
        guard enabled, let official, now.timeIntervalSince(official.fetchedAt) < grace else { return nil }
        return official
    }

    /// - official: `usableOfficial`을 거친 값
    /// - tokensSinceOfficial: 공식 조회 이후 로컬 소모분
    public static func evaluate(official: OfficialUsage?, officialEnabled: Bool,
                                blockTokens: Int, weeklyTokens: Int, tokensSinceOfficial: Int,
                                sessionLimit: Int, weeklyLimit: Int, burnRate: Double) -> Result {
        let since = official == nil ? 0 : tokensSinceOfficial
        let session = GaugeMath.reading(officialBase: official?.sessionPercent, windowTokens: blockTokens,
                                        tokensSince: since, estimatedLimit: sessionLimit)
        let weekly = GaugeMath.reading(officialBase: official?.weeklyPercent, windowTokens: weeklyTokens,
                                       tokensSince: since, estimatedLimit: weeklyLimit)
        let sessionRemaining = official?.sessionPercent
            .flatMap { GaugeMath.remainingTokens(base: $0, windowTokens: blockTokens, tokensSince: since) }
            ?? max(0, sessionLimit - blockTokens)

        // 연동 on인데 공식 값이 없으면(시작 직후·실패) 폴백 %가 순간 튀어
        // 오탐 알림·빨간 고양이가 나올 수 있으므로 평가를 보류한다.
        let authoritative = official != nil || !officialEnabled
        return Result(
            session: session,
            weekly: weekly,
            sessionMinutesLeft: GaugeMath.minutesUntilFull(remainingTokens: sessionRemaining, burnRate: burnRate),
            authoritative: authoritative,
            level: authoritative ? UsageAlertLevel.level(percent: max(session.percent, weekly.percent)) : .normal
        )
    }
}
