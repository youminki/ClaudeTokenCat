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

    private func input(_ official: OfficialUsage?, rate: Double? = nil) -> UsageEvaluator.Input {
        UsageEvaluator.Input(official: official, now: now, sessionRatePerMinute: rate)
    }

    @Test func usableOfficialRespectsToggleAndGrace() {
        let grace: TimeInterval = 15 * 60
        let fresh = official(session: 40, weekly: 20, minutesAgo: 10)
        #expect(UsageEvaluator.usableOfficial(fresh, enabled: true, now: now, grace: grace) == fresh)
        #expect(UsageEvaluator.usableOfficial(fresh, enabled: false, now: now, grace: grace) == nil)
        let old = official(session: 40, weekly: 20, minutesAgo: 16)
        #expect(UsageEvaluator.usableOfficial(old, enabled: true, now: now, grace: grace) == nil)
    }

    @Test func gaugesShowOfficialValuesAsIs() {
        let result = UsageEvaluator.evaluate(input(official(session: 40, weekly: 96)))
        #expect(result.session == GaugeReading(percent: 40, source: .official))
        #expect(result.weekly?.percent == 96)
        #expect(result.level == .critical)
        #expect(result.sessionResetsAt == now.addingTimeInterval(180 * 60))
        #expect(!result.needsRefresh)
    }

    // 공식 값이 없으면(연동 꺼짐, 조회 전·실패) 로컬 기록으로 추정하지 않고 게이지를 비운다.
    @Test func noOfficialMeansEmptyGauges() {
        let result = UsageEvaluator.evaluate(input(nil, rate: 1))
        #expect(result.session == nil)
        #expect(result.weekly == nil)
        #expect(result.sessionResetsAt == nil)
        #expect(result.sessionMinutesLeft == nil)
        #expect(result.level == .normal)
        #expect(!result.needsRefresh)
    }

    @Test func missingWindowStaysEmpty() {
        let result = UsageEvaluator.evaluate(input(official(session: nil, weekly: 85), rate: 1))
        #expect(result.session == nil)
        #expect(result.sessionResetsAt == nil)
        #expect(result.sessionMinutesLeft == nil)
        #expect(result.weekly?.percent == 85)
        #expect(result.level == .tired)
        #expect(!result.needsRefresh)
    }

    @Test func sessionOnlyResponse() {
        let result = UsageEvaluator.evaluate(input(official(session: 82, weekly: nil), rate: 0.5))
        #expect(result.weekly == nil)
        #expect(result.weeklyResetsAt == nil)
        #expect(result.session?.percent == 82)
        #expect(result.sessionMinutesLeft == 36)
        #expect(result.level == .tired)
        #expect(!result.needsRefresh)
    }

    // 조회할 때 이미 지난 리셋 시각이 왔으면 활성 창이 없다: 0%로 두고 지난 시각을 리셋으로 보여 주지 않는다.
    @Test func staleResetAtFetchIsNotShown() {
        let result = UsageEvaluator.evaluate(input(official(session: 55, weekly: 30, sessionResetsIn: -10)))
        #expect(result.session == GaugeReading(percent: 0, source: .official))
        #expect(result.sessionResetsAt == nil)
        #expect(result.weeklyResetsAt != nil)
        #expect(!result.needsRefresh)
    }

    @Test func rolledOverWindowAsksForRefresh() {
        // 세션 창이 30초 전에 초기화됐는데 공식 값은 그 전에 받았다
        let stale = official(session: 97, weekly: 30, minutesAgo: 2, sessionResetsIn: -0.5)
        let result = UsageEvaluator.evaluate(input(stale, rate: 1))
        #expect(result.session == GaugeReading(percent: 0, source: .rolledOver))
        #expect(result.sessionResetsAt == nil)
        #expect(result.sessionMinutesLeft == nil)
        #expect(result.needsRefresh)
        #expect(result.level == .normal)   // 예전 97%로 빨간 경고를 띄우지 않는다
    }

    @Test func minutesLeft() {
        // 공식 40%가 분당 0.6%p씩 오르면 100분
        #expect(UsageEvaluator.evaluate(input(official(session: 40, weekly: 10), rate: 0.6)).sessionMinutesLeft == 100)
        #expect(UsageEvaluator.evaluate(input(official(session: 40, weekly: 10))).sessionMinutesLeft == nil)
    }
}
