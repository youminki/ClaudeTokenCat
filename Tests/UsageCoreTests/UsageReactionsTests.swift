import Foundation
import Testing
@testable import UsageCore

struct UsageReactionsTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func input(_ t: TimeInterval, rate: Double = 500, idle: TimeInterval = 1, percent: Double? = 10,
                       window: String? = "w1", projects: Int = 1) -> UsageReactions.Input {
        .init(rate: rate, runThreshold: 2_000, idleSeconds: idle, sessionPercent: percent, sessionWindow: window,
              activeProjects: projects, now: start.addingTimeInterval(t))
    }

    @Test func burstNeedsAJumpAboveRunning() {
        var r = UsageReactions()
        #expect(r.update(input(0, rate: 800)) == nil)
        #expect(r.update(input(3, rate: 900)) == nil)
        #expect(r.update(input(6, rate: 4_500)) == .burst)
        // 높은 속도가 이어지기만 하면 다시 내지 않는다
        #expect(r.update(input(30, rate: 4_600)) == nil)
    }

    @Test func resumedAfterRest() {
        var r = UsageReactions()
        #expect(r.update(input(0, idle: 200)) == nil)
        #expect(r.update(input(3, idle: 2)) == .resumed)
    }

    @Test func milestonesOncePerWindowAndBaselineIsSilent() {
        var r = UsageReactions()
        #expect(r.update(input(0, percent: 40)) == nil)        // 처음 본 25% 단계는 기준
        #expect(r.update(input(20, percent: 49)) == nil)
        #expect(r.update(input(40, percent: 51)) == .sessionMilestone(50))
        #expect(r.update(input(60, percent: 52)) == nil)
        #expect(r.update(input(80, percent: 30, window: "w2")) == .newSession)
        #expect(r.update(input(100, percent: 55, window: "w2")) == .sessionMilestone(50))
    }

    @Test func cooldownAndMultitask() {
        var r = UsageReactions()
        #expect(r.update(input(0, projects: 1)) == nil)
        #expect(r.update(input(3, projects: 2)) == .multitask(2))
        #expect(r.update(input(6, projects: 1)) == nil)
        #expect(r.update(input(30, projects: 2)) == nil)        // 10분 안에는 다시 내지 않는다
        #expect(r.update(input(700, projects: 1)) == nil)
        #expect(r.update(input(703, projects: 3)) == .multitask(3))
    }

    @Test func firstTickOnlySetsBaseline() {
        var r = UsageReactions()
        // 앱을 켜자마자 지난 기록에 폴더가 둘 보여도 춤추지 않는다
        #expect(r.update(input(0, projects: 2)) == nil)
        #expect(r.update(input(3, projects: 2)) == nil)
    }

    @Test func milestoneBlockedByCooldownComesNext() {
        var r = UsageReactions()
        #expect(r.update(input(0, idle: 1, percent: 20)) == nil)
        #expect(r.update(input(3, idle: 200, percent: 20)) == nil)
        // 같은 틱에 다시 시작과 50%가 겹치면 다시 시작이 먼저, 50%는 쉬는 시간이 끝난 뒤
        #expect(r.update(input(6, idle: 1, percent: 55)) == .resumed)
        #expect(r.update(input(10, percent: 56)) == nil)
        #expect(r.update(input(22, percent: 57)) == .sessionMilestone(50))
    }

    @Test func tempoRisesWithinTier() {
        let t = Thresholds()
        #expect(t.tempo(burnRate: 2_000, state: .running) == 0.85)
        #expect(abs(t.tempo(burnRate: 6_000, state: .running) - 1.075) < 0.001)
        #expect(t.tempo(burnRate: 50_000, state: .running) == 1.3)
        #expect(t.tempo(burnRate: 0, state: .sleeping) == 1)
    }
}
