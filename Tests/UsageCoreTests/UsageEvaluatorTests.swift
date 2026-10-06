import Foundation
import Testing
@testable import UsageCore

struct UsageEvaluatorTests {

    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func official(session: Double?, weekly: Double?, minutesAgo: Double = 1,
                          sessionResetsIn: Double? = 180, weeklyResetsIn: Double? = 3 * 24 * 60) -> OfficialUsage {
        OfficialUsage(sessionPercent: session, sessionResetsAt: sessionResetsIn.map { now.addingTimeInterval($0 * 60) },
                      weeklyPercent: weekly, weeklyResetsAt: weeklyResetsIn.map { now.addingTimeInterval($0 * 60) },
                      fetchedAt: now.addingTimeInterval(-minutesAgo * 60))
    }

    private func input(_ official: OfficialUsage?, enabled: Bool = true, rate: Double? = nil, blockTokens: Int = 0,
                       weeklyTokens: Int = 0, tokenBurnRate: Double = 0) -> UsageEvaluator.Input {
        UsageEvaluator.Input(official: official, officialEnabled: enabled, now: now, sessionRatePerMinute: rate,
                             blockTokens: blockTokens, weeklyTokens: weeklyTokens,
                             sessionLimit: 500_000, weeklyLimit: 4_000_000, tokenBurnRate: tokenBurnRate)
    }

    @Test func usableOfficialRespectsToggleAndGrace() {
        let grace: TimeInterval = 15 * 60
        let fresh = official(session: 40, weekly: 20, minutesAgo: 10)
        #expect(UsageEvaluator.usableOfficial(fresh, enabled: true, now: now, grace: grace) == fresh)
        #expect(UsageEvaluator.usableOfficial(fresh, enabled: false, now: now, grace: grace) == nil)
        let old = official(session: 40, weekly: 20, minutesAgo: 16)
        #expect(UsageEvaluator.usableOfficial(old, enabled: true, now: now, grace: grace) == nil)
    }

    // 게이지는 공식 값만: 로컬 사용량(blockTokens)이 아무리 많아도 공식 %를 그대로 보여 준다.
    @Test func gaugesShowOfficialValuesOnly() {
        let result = UsageEvaluator.evaluate(input(official(session: 40, weekly: 96), blockTokens: 9_000_000))
        #expect(result.authoritative)
        #expect(result.session.percent == 40)
        #expect(result.session.source == .official)
        #expect(result.weekly.percent == 96)
        #expect(result.level == .critical)
        #expect(result.sessionResetsAt == now.addingTimeInterval(180 * 60))
        #expect(!result.needsRefresh)
    }

    @Test func holdsLevelWhileWaitingForOfficial() {
        // 연동 on인데 공식 값이 아직 없으면 추정 %가 튀어도 경고 단계로 올리지 않는다
        let result = UsageEvaluator.evaluate(input(nil, blockTokens: 900_000))
        #expect(!result.authoritative)
        #expect(abs(result.session.percent - 180) < 0.001)
        #expect(result.level == .normal)
    }

    @Test func disabledOfficialUsesEstimateAndIsAuthoritative() {
        let result = UsageEvaluator.evaluate(input(nil, enabled: false, blockTokens: 425_000, weeklyTokens: 1_000_000))
        #expect(result.authoritative)
        #expect(!result.session.isOfficial)
        #expect(abs(result.session.percent - 85) < 0.001)
        #expect(abs(result.weekly.percent - 25) < 0.001)
        #expect(result.level == .tired)
    }

    @Test func rolledOverWindowAsksForRefresh() {
        // 세션 창이 30초 전에 초기화됐는데 공식 값은 그 전에 받았다
        let stale = official(session: 97, weekly: 30, minutesAgo: 2, sessionResetsIn: -0.5)
        let result = UsageEvaluator.evaluate(input(stale, rate: 1))
        #expect(result.session.source == .rolledOver)
        #expect(result.session.percent == 0)
        #expect(result.sessionResetsAt == nil)
        #expect(result.sessionMinutesLeft == nil)
        #expect(result.needsRefresh)
        #expect(result.level == .normal)   // 예전 97%로 빨간 경고를 띄우지 않는다
    }

    @Test func minutesLeft() {
        // 공식 40%가 분당 0.6%p씩 오르면 100분
        #expect(UsageEvaluator.evaluate(input(official(session: 40, weekly: 10), rate: 0.6)).sessionMinutesLeft == 100)
        #expect(UsageEvaluator.evaluate(input(official(session: 40, weekly: 10))).sessionMinutesLeft == nil)
        // 추정 모드는 토큰 한도 기준
        let estimated = UsageEvaluator.evaluate(input(nil, enabled: false, blockTokens: 100_000, tokenBurnRate: 10_000))
        #expect(estimated.sessionMinutesLeft == 40)
        #expect(UsageEvaluator.evaluate(input(nil, enabled: false, blockTokens: 100_000)).sessionMinutesLeft == nil)
    }
}
