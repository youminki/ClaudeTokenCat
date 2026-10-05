import XCTest
@testable import UsageCore

final class UsageAlertsTests: XCTestCase {

    func testAlertLevels() {
        XCTAssertEqual(UsageAlertLevel.level(percent: 0), .normal)
        XCTAssertEqual(UsageAlertLevel.level(percent: 79.9), .normal)
        XCTAssertEqual(UsageAlertLevel.level(percent: 80), .tired)
        XCTAssertEqual(UsageAlertLevel.level(percent: 94.9), .tired)
        XCTAssertEqual(UsageAlertLevel.level(percent: 95), .critical)
    }

    func testEightyFiresExactlyOnce() {
        var tracker = LimitAlertTracker()
        XCTAssertEqual(tracker.alertsToFire(kind: .session, percent: 81, windowId: "w1"), [.eighty])
        XCTAssertEqual(tracker.alertsToFire(kind: .session, percent: 85, windowId: "w1"), [])
        XCTAssertEqual(tracker.alertsToFire(kind: .session, percent: 82, windowId: "w1"), [])
    }

    func testNinetyFiveAfterEighty() {
        var tracker = LimitAlertTracker()
        XCTAssertEqual(tracker.alertsToFire(kind: .session, percent: 81, windowId: "w1"), [.eighty])
        XCTAssertEqual(tracker.alertsToFire(kind: .session, percent: 96, windowId: "w1"), [.ninetyFive])
        XCTAssertEqual(tracker.alertsToFire(kind: .session, percent: 97, windowId: "w1"), [])
    }

    func testJumpStraightToNinetySixFiresOnlyNinetyFive() {
        var tracker = LimitAlertTracker()
        XCTAssertEqual(tracker.alertsToFire(kind: .session, percent: 96, windowId: "w1"), [.ninetyFive])
        // 건너뛴 80도 소진됨 — 이후 아무것도 재발송 없음
        XCTAssertEqual(tracker.alertsToFire(kind: .session, percent: 96, windowId: "w1"), [])
        XCTAssertEqual(tracker.alertsToFire(kind: .session, percent: 85, windowId: "w1"), [])
    }

    func testNewWindowResets() {
        var tracker = LimitAlertTracker()
        XCTAssertEqual(tracker.alertsToFire(kind: .session, percent: 85, windowId: "w1"), [.eighty])
        XCTAssertEqual(tracker.alertsToFire(kind: .session, percent: 85, windowId: "w2"), [.eighty])
    }

    func testSessionAndWeeklyIndependent() {
        var tracker = LimitAlertTracker()
        XCTAssertEqual(tracker.alertsToFire(kind: .session, percent: 85, windowId: "s1"), [.eighty])
        XCTAssertEqual(tracker.alertsToFire(kind: .weekly, percent: 85, windowId: "k1"), [.eighty])
    }

    func testBelowThresholdNeverFires() {
        var tracker = LimitAlertTracker()
        XCTAssertEqual(tracker.alertsToFire(kind: .weekly, percent: 79.9, windowId: "w"), [])
    }
}
