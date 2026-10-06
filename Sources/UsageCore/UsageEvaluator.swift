import Foundation

/// 틱 한 번의 판단: 공식 값을 쓸 수 있는지, 게이지 %, 한도 단계.
/// 엔진의 큐·타이머와 떼어 두어 단위 테스트한다.
public enum UsageEvaluator {

    /// 한 틱의 입력.
    public struct Input: Equatable, Sendable {
        /// `usableOfficial`을 거친 값. nil이면 게이지를 비운다.
        public var official: OfficialUsage?
        public var now: Date
        /// 최근 공식 세션 %의 오름세 (분당 %p). 한도까지 남은 시간 계산용.
        public var sessionRatePerMinute: Double?

        public init(official: OfficialUsage?, now: Date, sessionRatePerMinute: Double? = nil) {
            self.official = official
            self.now = now
            self.sessionRatePerMinute = sessionRatePerMinute
        }
    }

    public struct Result: Equatable, Sendable {
        /// 공식 값이 없으면 nil (연동 꺼짐, 조회 전·실패, 응답에 그 창이 없음).
        public let session: GaugeReading?
        public let weekly: GaugeReading?
        /// 게이지가 기준으로 삼는 창의 끝. 공식 창이 초기화됐으면 nil (새 창은 다음 조회에서 안다).
        public let sessionResetsAt: Date?
        public let weeklyResetsAt: Date?
        /// 현재 속도로 세션 한도에 닿기까지 남은 분. 속도가 없으면 nil.
        public let sessionMinutesLeft: Int?
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
        let sessionWindow = input.official?.sessionWindow
        let weeklyWindow = input.official?.weeklyWindow
        let session = sessionWindow.map { GaugeMath.reading(official: $0, now: input.now) }
        let weekly = weeklyWindow.map { GaugeMath.reading(official: $0, now: input.now) }
        var minutesLeft: Int?
        if let session, session.source == .official {
            minutesLeft = GaugeMath.minutesUntilFull(percent: session.percent, ratePerMinute: input.sessionRatePerMinute)
        }
        let highest = [session, weekly].compactMap { $0?.percent }.max() ?? 0
        return Result(
            session: session,
            weekly: weekly,
            sessionResetsAt: session?.source == .official ? sessionWindow?.upcomingReset : nil,
            weeklyResetsAt: weekly?.source == .official ? weeklyWindow?.upcomingReset : nil,
            sessionMinutesLeft: minutesLeft,
            level: UsageAlertLevel.level(percent: highest),
            needsRefresh: session?.source == .rolledOver || weekly?.source == .rolledOver
        )
    }
}

extension OfficialUsage {
    public var sessionWindow: OfficialWindow? {
        sessionPercent.map {
            OfficialWindow(percent: $0, resetsAt: sessionResetsAt, fetchedAt: fetchedAt)
        }
    }

    public var weeklyWindow: OfficialWindow? {
        weeklyPercent.map {
            OfficialWindow(percent: $0, resetsAt: weeklyResetsAt, fetchedAt: fetchedAt)
        }
    }
}
