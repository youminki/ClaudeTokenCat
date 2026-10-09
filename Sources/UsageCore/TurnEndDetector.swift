import Foundation

/// 새로 읽은 기록에서 Claude가 방금 대화 차례를 마친 때를 찾는다.
/// 한 응답이 여러 줄로 기록돼 같은 메시지가 여러 번 나오고, 앱을 켤 때는 지난 기록을 한꺼번에 읽으므로 둘 다 거른다.
public struct TurnEndDetector {
    /// 이보다 오래된 기록은 지금 끝난 것이 아니다.
    public var maxAge: TimeInterval = 60
    private var announced: Set<String> = []

    public init() {}

    /// 방금 끝난 차례들. 같은 메시지는 한 번만.
    public mutating func finishedTurns(in events: [UsageEvent], now: Date) -> [UsageEvent] {
        if announced.count > 1000 { announced.removeAll() }
        return events.filter { event in
            event.endsTurn && now.timeIntervalSince(event.timestamp) <= maxAge
                && announced.insert(event.messageId).inserted
        }
    }
}
