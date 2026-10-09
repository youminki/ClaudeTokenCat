import Foundation

/// 모델별 API 단가 (USD / 1M tokens). 모델명 프리픽스 매칭.
/// 모든 비용은 추정치 — UI에서 "(추정)" 라벨 필수.
public enum PricingTable {

    public struct Rates: Sendable {
        public let input: Double        // USD per 1M input tokens
        public let output: Double
        public let cacheWrite: Double
        public let cacheRead: Double
    }

    /// 모델 이름 접두어별 단가. 가장 긴 접두어가 이긴다.
    /// 지금 모델은 LiteLLM 데이터로 만든 `generated`(scripts/update-prices.py)를 쓰고,
    /// 그 데이터에 없는 옛 모델과 아직 표에 없는 새 모델을 위해 계열별 값을 손으로 둔다.
    static let table: [(prefix: String, rates: Rates)] = generated + fallback

    static let fallback: [(prefix: String, rates: Rates)] = [
        ("claude-fable",     Rates(input: 10,  output: 50, cacheWrite: 12.5,  cacheRead: 1)),
        ("claude-opus-4",    Rates(input: 15,  output: 75, cacheWrite: 18.75, cacheRead: 1.5)),
        ("claude-opus",      Rates(input: 5,   output: 25, cacheWrite: 6.25,  cacheRead: 0.5)),
        ("claude-sonnet",    Rates(input: 3,   output: 15, cacheWrite: 3.75,  cacheRead: 0.3)),
        ("claude-haiku",     Rates(input: 1,   output: 5,  cacheWrite: 1.25,  cacheRead: 0.1)),
        ("claude-3-5-haiku", Rates(input: 0.8, output: 4,  cacheWrite: 1,     cacheRead: 0.08)),
    ]

    public static func rates(forModel model: String) -> Rates? {
        table
            .filter { model.hasPrefix($0.prefix) }
            .max { $0.prefix.count < $1.prefix.count }?
            .rates
    }

    /// 이벤트 1건의 추정 비용(USD). 단가 미등록 모델은 0 (관용적 처리).
    public static func cost(of event: UsageEvent) -> Double {
        guard let r = rates(forModel: event.model) else { return 0 }
        let mtok = 1_000_000.0
        return Double(event.inputTokens) / mtok * r.input
            + Double(event.outputTokens) / mtok * r.output
            + Double(event.cacheCreationTokens) / mtok * r.cacheWrite
            + Double(event.cacheReadTokens) / mtok * r.cacheRead
    }
}
