import Foundation

/// 주간 창 시작 시각 (§2: 기본 롤링 7일, 사용자 리셋 요일/시각 설정 시 그 기준).
public enum WeeklyWindow {

    /// 사용자 설정 리셋(요일 1=일 ... 7=토, 로컬 시각) 기준 — 가장 최근 리셋 시각.
    public static func lastReset(weekday: Int, hour: Int,
                                 now: Date = Date(), calendar: Calendar = .current) -> Date {
        var components = DateComponents()
        components.weekday = weekday
        components.hour = hour
        components.minute = 0
        components.second = 0
        return calendar.nextDate(after: now, matching: components,
                                 matchingPolicy: .nextTime, direction: .backward) ?? now
    }

    /// 롤링 7일 창 시작.
    public static func rollingStart(now: Date = Date()) -> Date {
        now.addingTimeInterval(-7 * 24 * 60 * 60)
    }
}
