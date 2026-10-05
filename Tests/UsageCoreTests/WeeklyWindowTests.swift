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
}
