import Foundation

/// 한도 임박 단계 (§F2 오버라이드: 80% 🥵 지침, 95% ⚠️ 경고).
public enum UsageAlertLevel: Int, Comparable, Sendable {
    case normal = 0
    case tired = 1      // 사용률 80% 이상
    case critical = 2   // 사용률 95% 이상

    public static func level(percent: Double) -> UsageAlertLevel {
        if percent >= 95 { return .critical }
        if percent >= 80 { return .tired }
        return .normal
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// 80%/95% 알림을 창(세션/주간)별로 각 1회만 발송하도록 추적 (§F4, §7).
/// 창 식별자(windowId)가 바뀌면(리셋) 해당 종류의 기록을 새로 시작한다.
public struct LimitAlertTracker {

    public enum Kind: String, Sendable { case session, weekly }
    public enum Threshold: Int, Sendable { case eighty = 80, ninetyFive = 95 }

    private var sent: [Kind.RawValue: (windowId: String, thresholds: Set<Int>)] = [:]

    public init() {}

    /// 현재 사용률을 보고하고, 새로 발송해야 할 알림 임계값을 반환 (없으면 빈 배열).
    /// 70→96처럼 건너뛰면 95만 발송 (80은 함께 소진 처리해 스팸 방지).
    public mutating func alertsToFire(kind: Kind, percent: Double, windowId: String) -> [Threshold] {
        var record = sent[kind.rawValue] ?? (windowId, [])
        if record.windowId != windowId { record = (windowId, []) }   // 창 리셋 → 기록 초기화

        var fired: [Threshold] = []
        if percent >= 95, !record.thresholds.contains(95) {
            record.thresholds.formUnion([80, 95])
            fired.append(.ninetyFive)
        } else if percent >= 80, !record.thresholds.contains(80) {
            record.thresholds.insert(80)
            fired.append(.eighty)
        }
        sent[kind.rawValue] = record
        return fired
    }
}
