import Foundation

/// 틱 한 번의 판단: 공식 값을 쓸 수 있는지, 게이지 %, 한도 단계.
/// 엔진의 큐·타이머와 떼어 두어 단위 테스트한다.
public enum UsageEvaluator {

    public static let sessionDuration = BlockCalculator.blockDuration
    public static let weeklyDuration = WeeklyWindow.duration

    /// 한 틱의 입력.
    public struct Input: Equatable, Sendable {
        /// `usableOfficial`을 거친 값.
        public var official: OfficialUsage?
        public var officialEnabled: Bool
        public var now: Date
        /// 최근 공식 세션 %의 오름세 (분당 %p). 한도까지 남은 시간 계산용.
        public var sessionRatePerMinute: Double?
        // 추정 모드 (공식 값이 없을 때)
        public var blockTokens: Int
        public var weeklyTokens: Int
        public var sessionLimit: Int
        public var weeklyLimit: Int
        public var tokenBurnRate: Double

        public init(official: OfficialUsage?, officialEnabled: Bool, now: Date, sessionRatePerMinute: Double? = nil,
                    blockTokens: Int, weeklyTokens: Int, sessionLimit: Int, weeklyLimit: Int, tokenBurnRate: Double) {
            self.official = official
            self.officialEnabled = officialEnabled
            self.now = now
            self.sessionRatePerMinute = sessionRatePerMinute
            self.blockTokens = blockTokens
            self.weeklyTokens = weeklyTokens
            self.sessionLimit = sessionLimit
            self.weeklyLimit = weeklyLimit
            self.tokenBurnRate = tokenBurnRate
        }
    }

    public struct Result: Equatable, Sendable {
        public let session: GaugeReading
        public let weekly: GaugeReading
        /// 게이지가 기준으로 삼는 창의 끝. 공식 창이 초기화됐으면 nil (새 창은 다음 조회에서 안다).
        public let sessionResetsAt: Date?
        public let weeklyResetsAt: Date?
        /// 현재 속도로 세션 한도에 닿기까지 남은 분. 속도가 없으면 nil.
        public let sessionMinutesLeft: Int?
        /// 알림·고양이 오버라이드를 평가해도 되는지.
        public let authoritative: Bool
        public let level: UsageAlertLevel
        /// 공식 창이 조회 뒤 초기화돼 새 값을 받아야 하는지.
        public let needsRefresh: Bool
    }

    /// 연동이 켜져 있고 유예 시간 안에 받은 공식 값만 쓴다.
    public static func usableOfficial(_ official: OfficialUsage?, enabled: Bool, now: Date,
                                      grace: TimeInterval) -> OfficialUsage? {
        guard enabled, let official, now.timeIntervalSince(official.fetchedAt) < grace else { return nil }
        return official
    }

    public static func evaluate(_ input: Input) -> Result {
        let official = input.official
        let session = official?.sessionWindow.map { GaugeMath.reading(official: $0, now: input.now) }
            ?? GaugeMath.estimated(windowTokens: input.blockTokens, limit: input.sessionLimit)
        let weekly = official?.weeklyWindow.map { GaugeMath.reading(official: $0, now: input.now) }
            ?? GaugeMath.estimated(windowTokens: input.weeklyTokens, limit: input.weeklyLimit)

        let minutesLeft: Int?
        switch session.source {
        case .official:
            minutesLeft = GaugeMath.minutesUntilFull(percent: session.percent, ratePerMinute: input.sessionRatePerMinute)
        case .rolledOver:
            minutesLeft = nil
        case .estimated:
            minutesLeft = GaugeMath.minutesUntilFull(remainingTokens: max(0, input.sessionLimit - input.blockTokens),
                                                     burnRate: input.tokenBurnRate)
        }

        // 연동 on인데 공식 값이 없으면(시작 직후·실패) 폴백 %가 순간 튀어
        // 오탐 알림·빨간 고양이가 나올 수 있으므로 평가를 보류한다.
        let authoritative = official != nil || !input.officialEnabled
        let level = authoritative ? UsageAlertLevel.level(percent: max(session.percent, weekly.percent)) : .normal
        return Result(
            session: session,
            weekly: weekly,
            sessionResetsAt: session.source == .official ? official?.sessionResetsAt : nil,
            weeklyResetsAt: weekly.source == .official ? official?.weeklyResetsAt : nil,
            sessionMinutesLeft: minutesLeft,
            authoritative: authoritative,
            level: level,
            needsRefresh: session.source == .rolledOver || weekly.source == .rolledOver
        )
    }
}

extension OfficialUsage {
    public var sessionWindow: OfficialWindow? {
        sessionPercent.map {
            OfficialWindow(percent: $0, resetsAt: sessionResetsAt, fetchedAt: fetchedAt,
                           duration: UsageEvaluator.sessionDuration)
        }
    }

    public var weeklyWindow: OfficialWindow? {
        weeklyPercent.map {
            OfficialWindow(percent: $0, resetsAt: weeklyResetsAt, fetchedAt: fetchedAt,
                           duration: UsageEvaluator.weeklyDuration)
        }
    }
}
