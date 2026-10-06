import Foundation
import Testing
@testable import UsageCore

struct WeeklyWindowTests {

    private func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    @Test func rollingStart() {
        let now = date("2026-07-14T08:00:00Z")
        #expect(WeeklyWindow.rollingStart(now: now) == date("2026-07-07T08:00:00Z"))
    }

    @Test func nextResetRollsKnownResetForward() {
        let known = date("2026-07-09T04:40:00Z")
        // 아직 리셋 전이면 그대로
        #expect(WeeklyWindow.nextReset(from: known, now: date("2026-07-08T00:00:00Z")) == known)
        // 리셋이 지났으면 다음 주로
        #expect(WeeklyWindow.nextReset(from: known, now: date("2026-07-10T00:00:00Z")) == date("2026-07-16T04:40:00Z"))
        // 리셋 정각이면 다음 주가 다음 리셋
        #expect(WeeklyWindow.nextReset(from: known, now: known) == date("2026-07-16T04:40:00Z"))
        // 몇 주가 지나도 같은 요일·시각
        #expect(WeeklyWindow.nextReset(from: known, now: date("2026-07-30T00:00:00Z")) == date("2026-07-30T04:40:00Z"))
    }
}
