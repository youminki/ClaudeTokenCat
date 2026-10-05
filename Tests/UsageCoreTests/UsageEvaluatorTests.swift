import XCTest
@testable import UsageCore

final class UsageEvaluatorTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func official(session: Double?, weekly: Double?, minutesAgo: Double = 1) -> OfficialUsage {
        OfficialUsage(sessionPercent: session, sessionResetsAt: nil, weeklyPercent: weekly, weeklyResetsAt: nil,
                      fetchedAt: now.addingTimeInterval(-minutesAgo * 60))
    }

    func testUsableOfficialRespectsToggleAndGrace() {
        let grace: TimeInterval = 15 * 60
        let fresh = official(session: 40, weekly: 20, minutesAgo: 10)
        XCTAssertEqual(UsageEvaluator.usableOfficial(fresh, enabled: true, now: now, grace: grace), fresh)
        XCTAssertNil(UsageEvaluator.usableOfficial(fresh, enabled: false, now: now, grace: grace))
        let old = official(session: 40, weekly: 20, minutesAgo: 16)
        XCTAssertNil(UsageEvaluator.usableOfficial(old, enabled: true, now: now, grace: grace))
    }

    func testOfficialValuesDriveGaugesAndLevel() {
        let result = UsageEvaluator.evaluate(official: official(session: 40, weekly: 96), officialEnabled: true,
                                             blockTokens: 1_100_000, weeklyTokens: 5_000_000,
                                             tokensSinceOfficial: 100_000,
                                             sessionLimit: 500_000, weeklyLimit: 4_000_000, burnRate: 0)
        XCTAssertTrue(result.authoritative)
        XCTAssertEqual(result.session.percent, 44, accuracy: 0.001)   // 1% = 25,000 tokens
        XCTAssertTrue(result.weekly.isOfficial)
        XCTAssertEqual(result.level, .critical)                      // 주간 96%+ 보간
    }

    func testHoldsLevelWhileWaitingForOfficial() {
        // 연동 on인데 공식 값이 아직 없으면 추정 %가 튀어도 경고 단계로 올리지 않는다
        let result = UsageEvaluator.evaluate(official: nil, officialEnabled: true,
                                             blockTokens: 900_000, weeklyTokens: 0, tokensSinceOfficial: 0,
                                             sessionLimit: 500_000, weeklyLimit: 4_000_000, burnRate: 0)
        XCTAssertFalse(result.authoritative)
        XCTAssertEqual(result.session.percent, 180, accuracy: 0.001)
        XCTAssertEqual(result.level, .normal)
    }

    func testDisabledOfficialUsesEstimateAndIsAuthoritative() {
        let result = UsageEvaluator.evaluate(official: nil, officialEnabled: false,
                                             blockTokens: 425_000, weeklyTokens: 1_000_000,
                                             tokensSinceOfficial: 50_000,
                                             sessionLimit: 500_000, weeklyLimit: 4_000_000, burnRate: 0)
        XCTAssertTrue(result.authoritative)
        XCTAssertFalse(result.session.isOfficial)
        XCTAssertEqual(result.session.percent, 85, accuracy: 0.001)   // 공식 이후분은 추정에 쓰지 않는다
        XCTAssertEqual(result.weekly.percent, 25, accuracy: 0.001)
        XCTAssertEqual(result.level, .tired)
    }

    func testMinutesLeft() {
        // 공식 40%, 1% = 25,000 → 남은 56% = 1.4M, 분당 14,000이면 100분
        let live = UsageEvaluator.evaluate(official: official(session: 40, weekly: 10), officialEnabled: true,
                                           blockTokens: 1_100_000, weeklyTokens: 2_000_000,
                                           tokensSinceOfficial: 100_000,
                                           sessionLimit: 500_000, weeklyLimit: 4_000_000, burnRate: 14_000)
        XCTAssertEqual(live.sessionMinutesLeft, 100)
        // 공식 %가 작아 역산할 수 없으면 추정 한도로 계산한다
        let lowBase = UsageEvaluator.evaluate(official: official(session: 2, weekly: 10), officialEnabled: true,
                                              blockTokens: 100_000, weeklyTokens: 2_000_000, tokensSinceOfficial: 0,
                                              sessionLimit: 500_000, weeklyLimit: 4_000_000, burnRate: 10_000)
        XCTAssertEqual(lowBase.sessionMinutesLeft, 40)
        // 속도가 없으면 nil
        let idle = UsageEvaluator.evaluate(official: nil, officialEnabled: false,
                                           blockTokens: 100_000, weeklyTokens: 0, tokensSinceOfficial: 0,
                                           sessionLimit: 500_000, weeklyLimit: 4_000_000, burnRate: 0)
        XCTAssertNil(idle.sessionMinutesLeft)
    }
}
