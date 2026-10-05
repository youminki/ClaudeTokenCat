import Foundation

/// 주간 창 시작 시각 (§2: 기본 롤링 7일, 사용자 리셋 요일/시각 설정 시 그 기준).
public enum WeeklyWindow {

    public static let duration: TimeInterval = 7 * 24 * 60 * 60

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
        now.addingTimeInterval(-duration)
    }

    /// 알려진 리셋 시각(공식 응답)을 7일 단위로 굴려 `now` 이후 첫 리셋을 구한다.
    /// 공식 조회가 끊겨도 주간 창을 공식 창과 맞춰 두기 위해 쓴다.
    public static func nextReset(from knownReset: Date, now: Date = Date()) -> Date {
        let weeksPassed = (now.timeIntervalSince(knownReset) / duration).rounded(.down)
        return knownReset.addingTimeInterval((weeksPassed + 1) * duration)
    }
}
