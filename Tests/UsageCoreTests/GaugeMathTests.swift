import XCTest
@testable import UsageCore

final class GaugeMathTests: XCTestCase {

    // 실측 시나리오: 공식 63%, 조회 시점 블록 3.7M, 이후 300K 소모
    // → 1% ≈ 58,730 tokens → 보간 +5.1% ≈ 68.1%
    func testInterpolationUsesCalibratedScale() {
        let pct = GaugeMath.interpolated(base: 63, windowTokens: 4_000_000, tokensSince: 300_000)
        XCTAssertEqual(pct, 68.1, accuracy: 0.1)
    }

    func testNoInterpolationWhenNothingConsumedSinceFetch() {
        XCTAssertEqual(GaugeMath.interpolated(base: 63, windowTokens: 4_000_000, tokensSince: 0), 63)
    }

    func testLowBaseSkipsInterpolation() {
        // 공식 3%처럼 작으면 역산이 불안정 → 보간 없이 base 그대로 (100% 폭주 방지)
        XCTAssertEqual(GaugeMath.interpolated(base: 3, windowTokens: 200_000, tokensSince: 150_000), 3)
    }

    func testMissingWindowTokensSkipsInterpolation() {
        // 블록 없음(0) 또는 조회 이후분이 창 전체보다 큰 비정상 → base 그대로
        XCTAssertEqual(GaugeMath.interpolated(base: 50, windowTokens: 0, tokensSince: 100_000), 50)
        XCTAssertEqual(GaugeMath.interpolated(base: 50, windowTokens: 80_000, tokensSince: 100_000), 50)
    }

    func testCapsAtHundred() {
        let pct = GaugeMath.interpolated(base: 98, windowTokens: 1_000_000, tokensSince: 500_000)
        XCTAssertEqual(pct, 100)
        XCTAssertEqual(GaugeMath.interpolated(base: 120, windowTokens: 0, tokensSince: 0), 100)
    }

    func testRemainingTokens() {
        // 63% + 보간 5.1% = 68.1% → 남은 31.9% × 58,730 ≈ 1.87M
        let remaining = GaugeMath.remainingTokens(base: 63, windowTokens: 4_000_000, tokensSince: 300_000)
        XCTAssertEqual(Double(remaining ?? 0), 1_873_000, accuracy: 5_000)
        XCTAssertNil(GaugeMath.remainingTokens(base: 3, windowTokens: 100, tokensSince: 0))
    }
}
