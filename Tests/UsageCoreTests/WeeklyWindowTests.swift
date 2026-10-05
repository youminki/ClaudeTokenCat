import XCTest
@testable import UsageCore

final class WeeklyWindowTests: XCTestCase {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }

    private func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    func testLastResetSameWeek() {
        // 2026-07-14는 화요일(KST). 일요일 09:00 리셋 → 2026-07-12 09:00 KST (00:00 UTC)
        let now = date("2026-07-14T08:00:00Z")
        let reset = WeeklyWindow.lastReset(weekday: 1, hour: 9, now: now, calendar: calendar)
        XCTAssertEqual(reset, date("2026-07-12T00:00:00Z"))
    }

    func testLastResetExactlyNowGoesToPreviousWeek() {
        // 일요일 09:00 KST 정각 직후 → 그 시각이 최근 리셋
        let now = date("2026-07-12T00:00:01Z")
        let reset = WeeklyWindow.lastReset(weekday: 1, hour: 9, now: now, calendar: calendar)
        XCTAssertEqual(reset, date("2026-07-12T00:00:00Z"))
    }

    func testRollingStart() {
        let now = date("2026-07-14T08:00:00Z")
        XCTAssertEqual(WeeklyWindow.rollingStart(now: now), date("2026-07-07T08:00:00Z"))
    }

    func testNextResetRollsKnownResetForward() {
        let known = date("2026-07-09T04:40:00Z")
        // 아직 리셋 전이면 그대로
        XCTAssertEqual(WeeklyWindow.nextReset(from: known, now: date("2026-07-08T00:00:00Z")), known)
        // 리셋이 지났으면 다음 주로
        XCTAssertEqual(WeeklyWindow.nextReset(from: known, now: date("2026-07-10T00:00:00Z")),
                       date("2026-07-16T04:40:00Z"))
        // 리셋 정각이면 다음 주가 다음 리셋
        XCTAssertEqual(WeeklyWindow.nextReset(from: known, now: known), date("2026-07-16T04:40:00Z"))
        // 몇 주가 지나도 같은 요일·시각
        XCTAssertEqual(WeeklyWindow.nextReset(from: known, now: date("2026-07-30T00:00:00Z")),
                       date("2026-07-30T04:40:00Z"))
    }
}
