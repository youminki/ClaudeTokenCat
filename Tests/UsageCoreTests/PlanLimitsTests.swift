import XCTest
@testable import UsageCore

final class PlanLimitsTests: XCTestCase {

    func testPresetLimits() {
        XCTAssertEqual(PlanLimits.sessionLimit(plan: .pro, customLimit: nil, calibratedLimit: nil), 500_000)
        XCTAssertEqual(PlanLimits.sessionLimit(plan: .max5x, customLimit: nil, calibratedLimit: nil), 2_500_000)
        XCTAssertEqual(PlanLimits.sessionLimit(plan: .max20x, customLimit: nil, calibratedLimit: nil), 10_000_000)
    }

    func testPrecedenceCalibratedOverCustomOverPreset() {
        XCTAssertEqual(PlanLimits.sessionLimit(plan: .custom, customLimit: 800_000, calibratedLimit: nil), 800_000)
        XCTAssertEqual(PlanLimits.sessionLimit(plan: .custom, customLimit: 800_000, calibratedLimit: 1_200_000), 1_200_000)
        XCTAssertEqual(PlanLimits.sessionLimit(plan: .pro, customLimit: nil, calibratedLimit: 900_000), 900_000)
        // custom인데 입력 없음 → 안전 기본값
        XCTAssertEqual(PlanLimits.sessionLimit(plan: .custom, customLimit: nil, calibratedLimit: nil), 500_000)
    }

    func testCalibration() {
        // 창 토큰 1.2M, /usage 60% → 한도 2M
        XCTAssertEqual(PlanLimits.calibratedLimit(windowTokens: 1_200_000, usagePercent: 60), 2_000_000)
        XCTAssertNil(PlanLimits.calibratedLimit(windowTokens: 0, usagePercent: 60))
        XCTAssertNil(PlanLimits.calibratedLimit(windowTokens: 100, usagePercent: 0))
        XCTAssertNil(PlanLimits.calibratedLimit(windowTokens: 100, usagePercent: 101))
    }

    func testWeeklyLimit() {
        XCTAssertEqual(PlanLimits.weeklyLimit(sessionLimit: 500_000), 4_000_000)
        // 주간 캘리브레이션이 있으면 세션×8보다 우선
        XCTAssertEqual(PlanLimits.weeklyLimit(sessionLimit: 500_000, calibratedLimit: 9_000_000), 9_000_000)
        XCTAssertEqual(PlanLimits.weeklyLimit(sessionLimit: 500_000, calibratedLimit: 0), 4_000_000)
    }
}
