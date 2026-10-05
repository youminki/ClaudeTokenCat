import XCTest
@testable import UsageCore

final class BurnRateMeterTests: XCTestCase {

    func testEMASmoothing() {
        let meter = BurnRateMeter(alpha: 0.3)
        XCTAssertEqual(meter.update(tokensInLastMinute: 1000), 300, accuracy: 0.001)
        XCTAssertEqual(meter.update(tokensInLastMinute: 1000), 510, accuracy: 0.001)
        XCTAssertEqual(meter.update(tokensInLastMinute: 0), 357, accuracy: 0.001)
    }

    func testStateMachineThresholds() {
        let t = Thresholds()
        XCTAssertEqual(t.state(burnRate: 0, idleSeconds: 301), .sleeping)
        XCTAssertEqual(t.state(burnRate: 0, idleSeconds: 10), .walking)
        XCTAssertEqual(t.state(burnRate: 500, idleSeconds: 10), .walking)
        XCTAssertEqual(t.state(burnRate: 5_000, idleSeconds: 10), .running)
        XCTAssertEqual(t.state(burnRate: 15_000, idleSeconds: 10), .dashing)
        XCTAssertEqual(t.state(burnRate: 50_000, idleSeconds: 10), .rainbow)
    }

    func testSensitivityPresets() {
        let high = Thresholds.preset(sensitivity: .high)
        XCTAssertEqual(high.state(burnRate: 1_500, idleSeconds: 0), .running) // run 경계 1000으로 하향
        let low = Thresholds.preset(sensitivity: .low)
        XCTAssertEqual(low.state(burnRate: 3_000, idleSeconds: 0), .walking) // run 경계 4000으로 상향
    }
}
