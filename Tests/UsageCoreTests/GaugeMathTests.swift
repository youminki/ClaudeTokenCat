import Foundation
import Testing
@testable import UsageCore

struct GaugeMathTests {

    private let now = Date(timeIntervalSince1970: 1_000_000)
    private let fiveHours: TimeInterval = 5 * 3600

    private func window(_ percent: Double, resetsInMinutes: Double?, fetchedMinutesAgo: Double = 2) -> OfficialWindow {
        OfficialWindow(percent: percent, resetsAt: resetsInMinutes.map { now.addingTimeInterval($0 * 60) },
                       fetchedAt: now.addingTimeInterval(-fetchedMinutesAgo * 60), duration: fiveHours)
    }

    @Test func showsOfficialValueAsIs() {
        let reading = GaugeMath.reading(official: window(42, resetsInMinutes: 120), now: now)
        #expect(reading.percent == 42)
        #expect(reading.source == .official)
        #expect(reading.isOfficial)
    }

    // 회귀: 조회 뒤 창이 초기화되면 다음 조회까지 이전 창의 높은 %를 그대로 보여 줬다.
    @Test func dropsToZeroWhenWindowResetsAfterFetch() {
        let reading = GaugeMath.reading(official: window(97, resetsInMinutes: -0.5, fetchedMinutesAgo: 4), now: now)
        #expect(reading.percent == 0)
        #expect(reading.source == .rolledOver)
    }

    // 조회할 때 이미 지난 리셋 시각이 왔으면 활성 창이 없는 것: 0%, 다시 조회하지 않는다
    @Test func staleResetAtFetchMeansNoActiveWindow() {
        let reading = GaugeMath.reading(official: window(55, resetsInMinutes: -10, fetchedMinutesAgo: 2), now: now)
        #expect(reading.percent == 0)
        #expect(reading.source == .official)
    }

    @Test func clampsToRange() {
        #expect(GaugeMath.reading(official: window(120, resetsInMinutes: 60), now: now).percent == 100)
        #expect(GaugeMath.reading(official: window(-3, resetsInMinutes: 60), now: now).percent == 0)
        #expect(GaugeMath.reading(official: window(30, resetsInMinutes: nil), now: now).percent == 30)
    }

    @Test func displayPercentIsWhole() {
        #expect(GaugeReading(percent: 42.9, source: .official).displayPercent == 42)
        #expect(GaugeReading.estimated(1500).displayPercent == 999)
        #expect(GaugeReading.estimated(-3).displayPercent == 0)
    }

    @Test func estimatedReading() {
        #expect(GaugeMath.estimated(windowTokens: 250_000, limit: 500_000).percent == 50)
        #expect(GaugeMath.estimated(windowTokens: 10, limit: 0).percent == 0)
        #expect(!GaugeMath.estimated(windowTokens: 1, limit: 2).isOfficial)
    }

    @Test func impliedLimit() {
        #expect(GaugeMath.impliedLimit(percent: 40, windowTokens: 1_000_000) == 2_500_000)
        #expect(GaugeMath.impliedLimit(percent: 2, windowTokens: 1_000) == nil)
        #expect(GaugeMath.impliedLimit(percent: 40, windowTokens: 0) == nil)
    }

    @Test func minutesUntilFull() {
        // 40%에서 분당 0.6%p씩 오르면 남은 60%p는 100분
        #expect(GaugeMath.minutesUntilFull(percent: 40, ratePerMinute: 0.6) == 100)
        #expect(GaugeMath.minutesUntilFull(percent: 40, ratePerMinute: nil) == nil)
        #expect(GaugeMath.minutesUntilFull(percent: 40, ratePerMinute: 0) == nil)
        #expect(GaugeMath.minutesUntilFull(percent: 100, ratePerMinute: 1) == nil)
        #expect(GaugeMath.minutesUntilFull(remainingTokens: 600_000, burnRate: 10_000) == 60)
        #expect(GaugeMath.minutesUntilFull(remainingTokens: 0, burnRate: 10_000) == nil)
        #expect(GaugeMath.minutesUntilFull(remainingTokens: nil, burnRate: 10_000) == nil)
    }

    @Test func elapsedFraction() {
        // 리셋까지 2시간 남은 5시간 창 → 60% 경과
        #expect(abs(GaugeMath.elapsedFraction(resetsAt: now.addingTimeInterval(2 * 3600), duration: fiveHours,
                                              now: now) - 0.6) < 0.0001)
        #expect(GaugeMath.elapsedFraction(resetsAt: now.addingTimeInterval(-60), duration: fiveHours, now: now) == 1)
        #expect(GaugeMath.elapsedFraction(resetsAt: now.addingTimeInterval(9 * 3600), duration: fiveHours, now: now) == 0)
    }

    @Test func limitOutlookComparesWithReset() {
        let reset = now.addingTimeInterval(90 * 60)
        #expect(GaugeMath.limitOutlook(minutesLeft: 40, resetsAt: reset, now: now) == .reachesLimit(minutes: 40))
        // 한도보다 리셋이 먼저 오면 "N분 뒤 한도"는 의미가 없다
        #expect(GaugeMath.limitOutlook(minutesLeft: 120, resetsAt: reset, now: now) == .clearUntilReset)
        #expect(GaugeMath.limitOutlook(minutesLeft: 40, resetsAt: nil, now: now) == .reachesLimit(minutes: 40))
        #expect(GaugeMath.limitOutlook(minutesLeft: nil, resetsAt: reset, now: now) == nil)
        #expect(GaugeMath.limitOutlook(minutesLeft: 40, resetsAt: now.addingTimeInterval(-60), now: now)
                == .reachesLimit(minutes: 40))
    }
}

struct OfficialTrendTests {
    private let start = Date(timeIntervalSince1970: 2_000_000)

    private func window(_ percent: Double, minute: Double, resetMinute: Double = 300) -> OfficialWindow {
        OfficialWindow(percent: percent, resetsAt: start.addingTimeInterval(resetMinute * 60),
                       fetchedAt: at(minute), duration: 5 * 3600)
    }

    private func at(_ minute: Double) -> Date { start.addingTimeInterval(minute * 60) }

    @Test func rateFromRecentOfficialValues() {
        var trend = OfficialTrend()
        trend.record(window(20, minute: 0))
        trend.record(window(21, minute: 3))
        #expect(trend.ratePerMinute(now: at(3)) == nil)          // 5분이 안 됐고 2%p도 안 올랐다
        trend.record(window(26, minute: 12))
        #expect(trend.ratePerMinute(now: at(12)) == 0.5)          // 12분에 6%p
        #expect(trend.ratePerMinute(now: at(23)) == nil)          // 마지막 상승 뒤 10분 넘게 쉬는 중
    }

    @Test func restartsOnNewWindowOrDrop() {
        var trend = OfficialTrend()
        trend.record(window(90, minute: 0))
        trend.record(window(3, minute: 10, resetMinute: 600))    // 새 창
        trend.record(window(9, minute: 22, resetMinute: 600))
        #expect(trend.ratePerMinute(now: at(22)) == 0.5)
        trend.record(window(4, minute: 25, resetMinute: 600))    // 내려감 → 새로 센다
        #expect(trend.ratePerMinute(now: at(25)) == nil)
    }

    @Test func forgetsOldValues() {
        var trend = OfficialTrend()
        trend.record(window(10, minute: 0))
        trend.record(window(20, minute: 10))
        trend.record(window(20, minute: 50))   // 30분 넘게 지난 값은 버린다 → 변화 없음
        #expect(trend.ratePerMinute(now: at(50)) == nil)
    }

    @Test func toleratesResetJitter() {
        var trend = OfficialTrend()
        trend.record(window(10, minute: 0, resetMinute: 300))
        trend.record(window(16, minute: 6, resetMinute: 300.01))   // resets_at이 0.6초 흔들림
        #expect(trend.ratePerMinute(now: at(6)) == 1)
    }
}
