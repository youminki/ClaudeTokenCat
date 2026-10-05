import Foundation

/// 5시간 세션 블록. 첫 활동 시각을 UTC 정시로 내림한 시점부터 5시간 창 (ccusage 규칙).
public struct SessionBlock: Equatable, Sendable {
    public let start: Date
    public var end: Date { start.addingTimeInterval(BlockCalculator.blockDuration) }
    public var totalTokens: Int
    public var eventCount: Int

    public func contains(_ date: Date) -> Bool {
        date >= start && date < end
    }
}

public enum BlockCalculator {
    public static let blockDuration: TimeInterval = 5 * 60 * 60

    /// UTC 정시로 내림.
    public static func floorToUTCHour(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 3600).rounded(.down) * 3600)
    }

    /// 시간순 정렬된 이벤트를 5시간 블록으로 묶는다.
    /// 블록 시작 = 그 블록 첫 이벤트 시각의 UTC 정시 내림.
    /// 이벤트가 현재 블록 종료 이후면 새 블록 시작.
    public static func blocks(from events: [UsageEvent]) -> [SessionBlock] {
        var blocks: [SessionBlock] = []
        for event in events.sorted(by: { $0.timestamp < $1.timestamp }) {
            if var last = blocks.last, last.contains(event.timestamp) {
                last.totalTokens += event.totalTokens
                last.eventCount += 1
                blocks[blocks.count - 1] = last
            } else {
                blocks.append(SessionBlock(
                    start: floorToUTCHour(event.timestamp),
                    totalTokens: event.totalTokens,
                    eventCount: 1
                ))
            }
        }
        return blocks
    }

    /// 현재 시각이 속한 활성 블록. 마지막 블록이 이미 끝났으면 nil (세션 리셋됨).
    public static func currentBlock(from events: [UsageEvent], now: Date = Date()) -> SessionBlock? {
        guard let last = blocks(from: events).last, last.contains(now) else { return nil }
        return last
    }
}
