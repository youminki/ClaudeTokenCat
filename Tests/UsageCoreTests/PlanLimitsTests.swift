import Foundation
import Testing
@testable import UsageCore

struct PlanLimitsTests {

    @Test func presetLimits() {
        #expect(PlanLimits.sessionLimit(plan: .pro, customLimit: nil, calibratedLimit: nil) == 500_000)
        #expect(PlanLimits.sessionLimit(plan: .max5x, customLimit: nil, calibratedLimit: nil) == 2_500_000)
        #expect(PlanLimits.sessionLimit(plan: .max20x, customLimit: nil, calibratedLimit: nil) == 10_000_000)
    }

    @Test func precedenceCalibratedOverCustomOverPreset() {
        #expect(PlanLimits.sessionLimit(plan: .custom, customLimit: 800_000, calibratedLimit: nil) == 800_000)
        #expect(PlanLimits.sessionLimit(plan: .custom, customLimit: 800_000, calibratedLimit: 1_200_000) == 1_200_000)
        #expect(PlanLimits.sessionLimit(plan: .pro, customLimit: nil, calibratedLimit: 900_000) == 900_000)
        // custom인데 입력 없음 → 안전 기본값
        #expect(PlanLimits.sessionLimit(plan: .custom, customLimit: nil, calibratedLimit: nil) == 500_000)
    }

    @Test func calibration() {
        // 창 토큰 1.2M, /usage 60% → 한도 2M
        #expect(PlanLimits.calibratedLimit(windowTokens: 1_200_000, usagePercent: 60) == 2_000_000)
        #expect(PlanLimits.calibratedLimit(windowTokens: 0, usagePercent: 60) == nil)
        #expect(PlanLimits.calibratedLimit(windowTokens: 100, usagePercent: 0) == nil)
        #expect(PlanLimits.calibratedLimit(windowTokens: 100, usagePercent: 101) == nil)
    }

    @Test func weeklyLimit() {
        #expect(PlanLimits.weeklyLimit(sessionLimit: 500_000) == 4_000_000)
        // 주간 캘리브레이션이 있으면 세션×8보다 우선
        #expect(PlanLimits.weeklyLimit(sessionLimit: 500_000, calibratedLimit: 9_000_000) == 9_000_000)
        #expect(PlanLimits.weeklyLimit(sessionLimit: 500_000, calibratedLimit: 0) == 4_000_000)
    }
}
